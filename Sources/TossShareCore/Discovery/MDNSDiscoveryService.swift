//
//  MDNSDiscoveryService.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import Network

/// Layanan pemindai mDNS untuk mendeteksi perangkat Samsung Quick Share di jaringan lokal.
public final class MDNSDiscoveryService: @unchecked Sendable {

    public enum State: Sendable, Equatable {
        case stopped
        case scanning
        case failed(String)
    }

    public private(set) var state: State = .stopped
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.tossshare.mdns.discovery", qos: .utility)
    private weak var registry: DeviceRegistry?

    public init(registry: DeviceRegistry) {
        self.registry = registry
    }

    deinit {
        stopDiscovery()
    }

    // MARK: - Lifecycle

    /// Memulai pemindaian layanan mDNS Quick Share (`_FC9F5ED42C8A._tcp.`).
    public func startDiscovery() {
        guard state != .scanning else { return }

        let descriptor = NWBrowser.Descriptor.bonjour(
            type: TossShareCore.quickShareMDNSServiceType,
            domain: "local."
        )
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let newBrowser = NWBrowser(for: descriptor, using: parameters)
        self.browser = newBrowser

        newBrowser.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            switch newState {
            case .ready:
                self.state = .scanning
            case .failed(let error):
                self.state = .failed(error.localizedDescription)
            case .cancelled:
                self.state = .stopped
            default:
                break
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            self.handleBrowseResults(results)
        }

        newBrowser.start(queue: queue)
        self.state = .scanning
    }

    /// Menghentikan pemindaian mDNS.
    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        state = .stopped
    }

    // MARK: - Result Processing

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else {
                continue
            }

            let endpointId = name
            var friendlyName = "Samsung Device"
            var deviceType: DeviceType = .phone

            // Ekstraksi TXT Record jika tersedia dalam metadata Bonjour
            if case .bonjour(let txtRecord) = result.metadata {
                if let nRecord = txtRecord["n"], !nRecord.isEmpty {
                    if let parsed = try? EndpointInfoParser.parse(nRecord: nRecord) {
                        friendlyName = parsed.friendlyName
                        deviceType = parsed.deviceType
                    }
                }
            }

            // Konstruksi entitas PeerDevice
            let peer = PeerDevice(
                endpointId: endpointId,
                friendlyName: friendlyName,
                deviceType: deviceType,
                ipAddress: "local",
                port: 44445,
                lastSeen: Date()
            )

            Task { @MainActor [weak self] in
                self?.registry?.registerOrUpdate(device: peer)
            }
        }
    }
}
