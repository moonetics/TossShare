//
//  ShareViewController.swift
//  TossShareExtension
//
//  Created for TossShare for macOS.
//

import AppKit
import Foundation
import SwiftUI
import TossShareCore
import UniformTypeIdentifiers

/// View Controller utama untuk Finder Share Extension (`com.apple.share-services`).
/// Saat pengguna memilih berkas di Finder > Share > TossShare, view controller ini diaktifkan
/// untuk memuat berkas terpilih dan menyajikan antarmuka pemilihan perangkat target.
open class ShareViewController: NSViewController {
    private var itemURLs: [URL] = []
    private var hostingView: NSHostingView<ShareSheetPickerView>?

    open override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 380))
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
    }

    // MARK: - NSExtensionRequestHandling

    open override func beginRequest(with context: NSExtensionContext) {
        guard let inputItems = context.inputItems as? [NSExtensionItem], !inputItems.isEmpty else {
            context.cancelRequest(withError: NSError(domain: "TossShareExtension", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tidak ada berkas yang dipilih."]))
            return
        }

        Task {
            let extractedURLs = await extractURLs(from: inputItems)
            await MainActor.run {
                self.itemURLs = extractedURLs
                self.setupInterface()
            }
        }
    }

    @MainActor
    private func setupInterface() {
        let pickerView = ShareSheetPickerView(
            itemURLs: self.itemURLs,
            onSend: { [weak self] device, urls in
                self?.executeSend(to: device, items: urls)
            },
            onCancel: { [weak self] in
                let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
                self?.extensionContext?.cancelRequest(withError: error)
            }
        )

        let hosting = NSHostingView(rootView: pickerView)
        hosting.frame = self.view.bounds
        hosting.autoresizingMask = [.width, .height]
        self.view.addSubview(hosting)
        self.hostingView = hosting
    }

    @MainActor
    private func executeSend(to device: PeerDevice, items: [URL]) {
        let transferItems: [TransferItem] = items.map { url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 1024
            return TransferItem(
                fileName: url.lastPathComponent,
                mimeType: "application/octet-stream",
                fileSize: size,
                localURL: url
            )
        }

        let sender = NearbySenderSession(
            peerEndpointId: device.endpointId,
            items: transferItems
        )

        sender.onStateChange = { [weak self] (session: TransferSession) in
            Task { @MainActor in
                guard let self else { return }
                if session.state == .completed {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                } else if session.state == .failed || session.state == .cancelled {
                    let error = NSError(domain: "TossShareExtension", code: -2, userInfo: [NSLocalizedDescriptionKey: "Transfer gagal."])
                    self.extensionContext?.cancelRequest(withError: error)
                }
            }
        }

        Task {
            do {
                try await sender.start(device: device)
            } catch {
                await MainActor.run {
                    self.extensionContext?.cancelRequest(withError: error)
                }
            }
        }
    }

    private func extractURLs(from inputItems: [NSExtensionItem]) async -> [URL] {
        var urls: [URL] = []

        for item in inputItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                // Periksa apakah provider mendukung file URL
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let loadedURL = await loadURL(from: provider, typeIdentifier: UTType.fileURL.identifier) {
                        urls.append(loadedURL)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                    if let loadedURL = await loadURL(from: provider, typeIdentifier: UTType.item.identifier) {
                        urls.append(loadedURL)
                    }
                }
            }
        }

        return urls
    }

    private func loadURL(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let string = String(data: data, encoding: .utf8), let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
