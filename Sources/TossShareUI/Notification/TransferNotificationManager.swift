//
//  TransferNotificationManager.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import AppKit
import Foundation
import TossShareCore
import UserNotifications

/// Kategori notifikasi TossShare
public enum TossShareNotificationCategory {
    public static let incomingTransfer = "TOSSSHARE_INCOMING_TRANSFER"
    public static let transferSuccess = "TOSSSHARE_TRANSFER_SUCCESS"
    public static let transferFailed = "TOSSSHARE_TRANSFER_FAILED"
}

/// Identifikasi aksi notifikasi TossShare
public enum TossShareNotificationAction {
    public static let accept = "TOSSSHARE_ACTION_ACCEPT"
    public static let decline = "TOSSSHARE_ACTION_DECLINE"
    public static let showInFinder = "TOSSSHARE_ACTION_SHOW_IN_FINDER"
}

/// Pengelola notifikasi sistem macOS native berbasis `UNUserNotificationCenter`.
/// Menyajikan banner interaktif dengan tombol "Terima" & "Tolak", serta aksi "Tampilkan di Finder".
/// Mendukung fallback in-app modal bila otorisasi notifikasi dinonaktifkan atau Focus/DND aktif.
@MainActor
public final class TransferNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = TransferNotificationManager()

    @Published public private(set) var isAuthorized: Bool = false
    @Published public var fallbackIncomingSession: TransferSession?
    @Published public var fallbackSenderDevice: PeerDevice?

    // Handler callbacks untuk event persetujuan pengguna
    public var onTransferDecision: (@MainActor (UUID, Bool) -> Void)?
    public var onShowInFinder: (@MainActor ([URL]) -> Void)?

    private var activeSessions: [UUID: (session: TransferSession, device: PeerDevice)] = [:]
    private var completedFiles: [UUID: [URL]] = [:]
    private var pendingContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]

    public var isBundleEnvironment: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    public override init() {
        super.init()
        if isBundleEnvironment {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            setupCategories()
        }
    }

    /// Meminta persetujuan pengguna untuk transfer masuk secara asynchronous (via notifikasi atau in-app fallback).
    public func requestAcceptance(
        session: TransferSession,
        from device: PeerDevice,
        timeoutSeconds: Double = 30.0
    ) async -> Bool {
        postIncomingTransfer(session: session, from: device)

        return await withCheckedContinuation { continuation in
            self.pendingContinuations[session.sessionId] = continuation

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                await MainActor.run {
                    if let pending = self.pendingContinuations.removeValue(forKey: session.sessionId) {
                        pending.resume(returning: false)
                        self.dismissFallbackModal()
                    }
                }
            }
        }
    }

    /// Menyelesaikan keputusan penerimaan secara manual dari in-app UI atau delegat.
    public func resolveDecision(sessionId: UUID, accepted: Bool) {
        if let continuation = pendingContinuations.removeValue(forKey: sessionId) {
            continuation.resume(returning: accepted)
        }
        onTransferDecision?(sessionId, accepted)
        dismissFallbackModal()
    }

    /// Konfigurasi kategori dan aksi interaktif pada notifikasi sistem macOS.
    public func setupCategories() {
        guard isBundleEnvironment else { return }

        let acceptAction = UNNotificationAction(
            identifier: TossShareNotificationAction.accept,
            title: "Terima",
            options: [.foreground]
        )

        let declineAction = UNNotificationAction(
            identifier: TossShareNotificationAction.decline,
            title: "Tolak",
            options: [.destructive]
        )

        let incomingCategory = UNNotificationCategory(
            identifier: TossShareNotificationCategory.incomingTransfer,
            actions: [acceptAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let showAction = UNNotificationAction(
            identifier: TossShareNotificationAction.showInFinder,
            title: "Tampilkan di Finder",
            options: [.foreground]
        )

        let successCategory = UNNotificationCategory(
            identifier: TossShareNotificationCategory.transferSuccess,
            actions: [showAction],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([incomingCategory, successCategory])
    }

    /// Meminta izin notifikasi ke sistem macOS.
    public func requestAuthorization() async -> Bool {
        guard isBundleEnvironment else {
            self.isAuthorized = false
            return false
        }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            self.isAuthorized = granted
            return granted
        } catch {
            self.isAuthorized = false
            return false
        }
    }

    /// Memeriksa status izin terkini.
    public func checkAuthorizationStatus() async -> Bool {
        guard isBundleEnvironment else {
            self.isAuthorized = false
            return false
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let granted = settings.authorizationStatus == .authorized
        self.isAuthorized = granted
        return granted
    }

    /// Menampilkan notifikasi permintaan berkas masuk dari perangkat Samsung.
    public func postIncomingTransfer(session: TransferSession, from device: PeerDevice) {
        activeSessions[session.sessionId] = (session, device)

        // Jika notifikasi tidak diizinkan atau running bare binary tanpa .app bundle, gunakan fallback in-app modal
        if !isBundleEnvironment || !isAuthorized {
            self.fallbackIncomingSession = session
            self.fallbackSenderDevice = device
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "TossShare - Permintaan Masuk"
        let count = session.items.count
        let sizeFormatted = ByteCountFormatter.string(fromByteCount: session.totalBytes, countStyle: .file)
        content.body = "\(device.friendlyName) ingin mengirim \(count) berkas (\(sizeFormatted))."
        content.categoryIdentifier = TossShareNotificationCategory.incomingTransfer
        content.sound = .default
        content.userInfo = [
            "sessionId": session.sessionId.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: session.sessionId.uuidString,
            content: content,
            trigger: nil // Tampilkan instan
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if error != nil {
                Task { @MainActor in
                    self?.fallbackIncomingSession = session
                    self?.fallbackSenderDevice = device
                }
            }
        }
    }

    /// Menampilkan notifikasi transfer sukses dengan opsi buka di Finder.
    public func postTransferSuccess(session: TransferSession, from device: PeerDevice, savedURLs: [URL]) {
        completedFiles[session.sessionId] = savedURLs

        guard isBundleEnvironment && isAuthorized else {
            // Jika notifikasi dimatikan atau running bare CLI binary, buka Finder langsung bila ada file
            if let first = savedURLs.first {
                NSWorkspace.shared.activateFileViewerSelecting([first])
            }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "TossShare - Transfer Selesai"
        let count = session.items.count
        content.body = "\(count) berkas berhasil diterima dari \(device.friendlyName)."
        content.categoryIdentifier = TossShareNotificationCategory.transferSuccess
        content.sound = .default
        content.userInfo = [
            "sessionId": session.sessionId.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: "success-\(session.sessionId.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Menampilkan notifikasi kegagalan transfer.
    public func postTransferFailed(session: TransferSession, reason: String) {
        guard isBundleEnvironment && isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "TossShare - Transfer Gagal"
        content.body = "Transfer berkas terhenti: \(reason)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "failed-\(session.sessionId.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Membersihkan modal fallback in-app.
    public func dismissFallbackModal() {
        self.fallbackIncomingSession = nil
        self.fallbackSenderDevice = nil
    }

    // MARK: - UNUserNotificationCenterDelegate

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Tetap tampilkan banner dan suara meskipun app berada di foreground
        return [.banner, .sound, .badge]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let sessionIdString = userInfo["sessionId"] as? String,
              let sessionId = UUID(uuidString: sessionIdString) else {
            return
        }

        let actionId = response.actionIdentifier

        await MainActor.run {
            switch actionId {
            case TossShareNotificationAction.accept:
                self.resolveDecision(sessionId: sessionId, accepted: true)

            case TossShareNotificationAction.decline:
                self.resolveDecision(sessionId: sessionId, accepted: false)

            case TossShareNotificationAction.showInFinder, UNNotificationDefaultActionIdentifier:
                if let urls = self.completedFiles[sessionId], !urls.isEmpty {
                    self.onShowInFinder?(urls)
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                } else if let downloadDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadDir.path)
                }

            default:
                break
            }
        }
    }
}
