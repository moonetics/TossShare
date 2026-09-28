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
            self.handleBrowseResults(results, changes: changes)
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

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        // Tangani penghapusan service instance secara real-time
        for change in changes {
            if case .removed(let result) = change {
                if case .service(let name, _, _, _) = result.endpoint {
                    let cleanId = EndpointInfoParser.extractEndpointId(fromMdnsInstanceName: name) ?? name
                    Task { @MainActor [weak self] in
                        self?.registry?.removeDevice(endpointId: cleanId)
                        self?.registry?.removeDevice(endpointId: name)
                    }
                }
            }
        }

        let myName = Host.current().localizedName ?? ""
        let myHostname = ProcessInfo.processInfo.hostName

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else {
                continue
            }

            let endpointId = EndpointInfoParser.extractEndpointId(fromMdnsInstanceName: name) ?? name

            // 1. Filter out self-advertisement (Mac tidak boleh menampilkan dirinya sendiri di Radar)
            if ActiveServerTracker.shared.isSelf(instanceNameOrEndpointId: name) ||
               ActiveServerTracker.shared.isSelf(instanceNameOrEndpointId: endpointId) {
                continue
            }
            if !myName.isEmpty && (name == myName || name.contains(myName)) {
                continue
            }
            if !myHostname.isEmpty && name.contains(myHostname) {
                continue
            }
            if name.contains("MacBook") || name.contains("TossShare") {
                continue
            }

            var friendlyName = "Samsung Galaxy"
            var deviceType: DeviceType = .phone
            var ipAddress = "mDNS"
            var isPrivacyMode = false

            // 2. Ekstraksi TXT Record jika tersedia dalam metadata Bonjour (Case-Insensitive)
            if case .bonjour(let txtRecord) = result.metadata {
                for (key, val) in txtRecord.dictionary {
                    let k = key.lowercased()
                    if k == "n", !val.isEmpty {
                        if let parsed = try? EndpointInfoParser.parse(nRecord: val) {
                            friendlyName = parsed.friendlyName
                            deviceType = parsed.deviceType
                            isPrivacyMode = parsed.isPrivacyMode
                        }
                    } else if (k == "ipv4" || k == "ip"), !val.isEmpty {
                        ipAddress = val
                    }
                }
            }

            // Validasi nama hasil parse TXT record agar tidak menampilkan nama Mac sendiri
            if !myName.isEmpty && (friendlyName == myName || friendlyName.contains(myName)) {
                continue
            }
            if friendlyName.contains("MacBook") || friendlyName.contains("TossShare") {
                continue
            }

            print("📡 \u{001B}[1;36m[MDNS-DISCOVERY]\u{001B}[0m Perangkat ditemukan: '\(friendlyName)' (id: \(name), privasi: \(isPrivacyMode))")

            // Konstruksi entitas PeerDevice dengan referensi native NWEndpoint
            let peer = PeerDevice(
                endpointId: endpointId,
                friendlyName: friendlyName,
                deviceType: deviceType,
                ipAddress: ipAddress,
                port: 0,
                lastSeen: Date(),
                isPrivacyMode: isPrivacyMode,
                endpoint: result.endpoint
            )

            Task { @MainActor [weak self] in
                self?.registry?.registerOrUpdate(device: peer)
            }

            // 3. Resolusi Proaktif di Background (DEC-002, DEC-003, FR-002, FR-003)
            let capturedName = name
            let capturedPrivacyMode = isPrivacyMode
            Task.detached(priority: .utility) { [weak self] in
                guard let self = self else { return }
                let resolvedEndpoints = await NearbyBonjourServiceResolver.resolve(name: capturedName)
                if let target = resolvedEndpoints.first(where: \.isIPv4) {
                    var resolvedHostname: String? = nil
                    if capturedPrivacyMode {
                        resolvedHostname = await NearbyHostLookup.lookupHostname(forIPv4: target.host)
                    }
                    await self.registry?.updateResolvedEndpoint(
                        endpointId: capturedName,
                        ip: target.host,
                        port: target.port,
                        hostname: resolvedHostname
                    )
                }
            }
        }
    }
}
