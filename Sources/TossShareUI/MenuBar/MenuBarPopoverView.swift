//
//  MenuBarPopoverView.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI
import UniformTypeIdentifiers
import TossShareCore
import AppKit

/// Popover ringkas dari status item menu bar macOS yang menyediakan area drop cepat dan status perangkat.
public struct MenuBarPopoverView: View {

    @ObservedObject public var registry: DeviceRegistry
    @ObservedObject public var advisor: ConnectivityAdvisor
    public var onOpenRadarWindow: (() -> Void)?

    @State private var isTargetedForDrop: Bool = false
    @State private var hoveredEndpointId: String?
    @State private var activeTransferSession: TransferSession?
    @State private var activeSender: NearbySenderSession?

    public init(
        registry: DeviceRegistry,
        advisor: ConnectivityAdvisor,
        onOpenRadarWindow: (() -> Void)? = nil
    ) {
        self.registry = registry
        self.advisor = advisor
        self.onOpenRadarWindow = onOpenRadarWindow
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Header Status
            headerSection

            Divider()

            // Area Drop Zone Cepat
            quickDropZoneSection

            // Transfer Aktif (jika ada)
            if let activeSession = activeTransferSession {
                activeTransferProgressSection(session: activeSession)
            }

            Divider()

            // Daftar Perangkat Sekitar
            nearbyDevicesSection

            Divider()

            // Footer Aksi
            footerActions
        }
        .padding(Theme.Spacing.md)
        .frame(width: 320)
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack {
            Image(systemName: "arrow.triangle.swap")
                .foregroundColor(Theme.Colors.accentAirDrop)

            Text("TossShare")
                .font(Theme.Typography.deviceTitle)
                .fontWeight(.bold)

            Spacer()

            if advisor.shouldShowFallbackCard {
                StatusPillBadge(type: .warning("AP Isolation"))
            } else {
                StatusPillBadge(type: .ready)
            }
        }
    }

    private var quickDropZoneSection: some View {
        VStack(spacing: 6) {
            Image(systemName: isTargetedForDrop ? "arrow.down.circle.fill" : "plus.circle")
                .font(.system(size: 24))
                .foregroundColor(isTargetedForDrop ? Theme.Colors.accentSamsung : .secondary)

            Text(isTargetedForDrop ? "Lepas untuk mengirim!" : "Tarik berkas ke sini")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radii.small)
                .strokeBorder(
                    isTargetedForDrop ? Theme.Colors.accentSamsung : Theme.Colors.borderSubtle,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5])
                )
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radii.small)
                        .fill(isTargetedForDrop ? Theme.Colors.accentSamsung.opacity(0.08) : Color.clear)
                )
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargetedForDrop) { providers in
            // Jika ada perangkat pertama/terdekat, kirim ke perangkat tersebut
            if let target = registry.devices.first {
                return handleDroppedFile(providers: providers, targetDevice: target)
            }
            return false
        }
    }

    private func activeTransferProgressSection(session: TransferSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.items.first?.fileName ?? "Berkas")
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer()

                Text(session.state == .waitingAcceptance ? "Menunggu konfirmasi..." : "\(Int(session.progress * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(session.state == .waitingAcceptance ? Theme.Colors.accentSamsung : .secondary)
            }

            ProgressView(value: session.progress)
                .progressViewStyle(.linear)

            if !session.authPin.isEmpty {
                Text("PIN: \(session.authPin)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.Colors.accentSamsung)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radii.small)
                .fill(Theme.Colors.surfaceCard)
        )
        .transition(.opacity)
    }

    private var nearbyDevicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Perangkat Sekitar")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)

            if registry.devices.isEmpty {
                HStack {
                    Spacer()
                    Text("Belum ada perangkat terdeteksi")
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                    Spacer()
                }
            } else {
                ForEach(registry.devices.prefix(4)) { device in
                    let isHovered = hoveredEndpointId == device.endpointId
                    let displayName = registry.displayName(for: device)

                    HStack(spacing: 8) {
                        Image(systemName: deviceIconName(for: device.deviceType))
                            .foregroundColor(Theme.Colors.accentAirDrop)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayName)
                                .font(Theme.Typography.deviceTitle)
                                .lineLimit(1)

                            if device.isPrivacyMode {
                                Text("Mode Privasi")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else if let rssi = device.rssi {
                                Text("\(rssi) dBm")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            sendClipboardText(to: device)
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("Kirim Teks Clipboard ke \(displayName)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radii.small)
                            .fill(isHovered ? Theme.Colors.accentSamsung.opacity(0.12) : Color.clear)
                    )
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: Binding(
                        get: { hoveredEndpointId == device.endpointId },
                        set: { isHovered in hoveredEndpointId = isHovered ? device.endpointId : nil }
                    )) { providers in
                        handleDroppedFile(providers: providers, targetDevice: device)
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        VStack(spacing: 8) {
            if let firstDevice = registry.devices.first {
                let firstName = registry.displayName(for: firstDevice)
                Button {
                    sendClipboardText(to: firstDevice)
                } label: {
                    Label("Kirim Clipboard ke \(firstName)", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }

            HStack {
                Button {
                    onOpenRadarWindow?()
                } label: {
                    Label("Buka Radar", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accentAirDrop)

                Spacer()

                Button("Keluar") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }

    private func sendClipboardText(to device: PeerDevice) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        Task {
            _ = try? await NearbySenderSession.sendClipboardText(text, to: device)
        }
    }

    // MARK: - Helpers

    private func deviceIconName(for type: DeviceType) -> String {
        switch type {
        case .phone: return "iphone.gen3"
        case .tablet: return "ipad.gen2"
        case .laptop: return "laptopcomputer"
        case .unknown: return "display"
        }
    }

    private func handleDroppedFile(providers: [NSItemProvider], targetDevice: PeerDevice) -> Bool {
        guard !providers.isEmpty else { return false }

        let group = DispatchGroup()
        let collector = URLCollector()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { group.leave() }
                if let fileURL = url {
                    collector.append(fileURL)
                }
            }
        }

        group.notify(queue: .main) {
            let flattened = FileItemCollector.flattenURLs(collector.getAll())
            guard !flattened.isEmpty else { return }

            TossShareHaptics.performDropSnapped()

            let items = flattened.compactMap { fileURL -> TransferItem? in
                let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 1024
                return TransferItem(
                    fileName: fileURL.lastPathComponent,
                    mimeType: "application/octet-stream",
                    fileSize: size,
                    localURL: fileURL
                )
            }
            guard !items.isEmpty else { return }

            let sender = NearbySenderSession(peerEndpointId: targetDevice.endpointId, items: items)
            self.activeSender = sender
            self.activeTransferSession = sender.session

            sender.onProgressUpdate = { session in
                Task { @MainActor in
                    self.activeTransferSession = session
                }
            }

            sender.onStateChange = { session in
                Task { @MainActor in
                    self.activeTransferSession = session
                    if session.state == .completed {
                        TossShareHaptics.performSuccess()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            if self.activeTransferSession?.sessionId == session.sessionId {
                                self.activeTransferSession = nil
                                self.activeSender = nil
                            }
                        }
                    } else if session.state == .failed {
                        TossShareHaptics.performWarning()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            if self.activeTransferSession?.sessionId == session.sessionId {
                                self.activeTransferSession = nil
                                self.activeSender = nil
                            }
                        }
                    }
                }
            }

            Task {
                do {
                    try await sender.start(device: targetDevice)
                } catch {
                    Task { @MainActor in
                        var failed = sender.session
                        failed.fail(with: error.localizedDescription)
                        self.activeTransferSession = failed
                    }
                }
            }
        }
        return true
    }
}
