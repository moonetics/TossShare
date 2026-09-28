//
//  NetworkHealthMonitor.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import Network

/// Memantau antarmuka jaringan dan mendeteksi anomali seperti AP / Client Isolation.
public final class NetworkHealthMonitor: @unchecked Sendable {

    public private(set) var isWiFiActive: Bool = false
    public private(set) var isHotspotOrTethered: Bool = false
    public private(set) var isAPIsolationSuspected: Bool = false

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.tossshare.network.health", qos: .utility)
    private var failedConnectionAttempts: Int = 0

    public var onStatusChange: (@Sendable () -> Void)?

    public init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring Lifecycle

    public func startMonitoring() {
        guard monitor == nil else { return }

        let newMonitor = NWPathMonitor()
        newMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.handlePathUpdate(path)
        }
        newMonitor.start(queue: queue)
        self.monitor = newMonitor
    }

    public func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    private func handlePathUpdate(_ path: NWPath) {
        let hasWiFi = path.usesInterfaceType(.wifi)
        let hasCellular = path.usesInterfaceType(.cellular)
        let hasWired = path.usesInterfaceType(.wiredEthernet)

        self.isWiFiActive = (path.status == .satisfied && hasWiFi)
        self.isHotspotOrTethered = (hasCellular || (hasWired && !hasWiFi))

        onStatusChange?()
    }

    // MARK: - AP Isolation Diagnostics

    /// Melaporkan kegagalan koneksi TCP ke perangkat yang terlihat di mDNS.
    /// Jika terjadi kegagalan berulang padahal mDNS aktif, sistem menandai indikasi AP Isolation.
    public func reportTCPConnectionFailure() {
        failedConnectionAttempts += 1
        if failedConnectionAttempts >= 2 {
            isAPIsolationSuspected = true
            onStatusChange?()
        }
    }

    /// Reset status kecurigaan isolasi saat koneksi berhasil atau jaringan berganti.
    public func resetDiagnostics() {
        failedConnectionAttempts = 0
        isAPIsolationSuspected = false
        onStatusChange?()
    }

    /// Mengaktifkan atau mematikan simulasi AP Isolation untuk keperluan pengujian dan visualisasi UI.
    public func simulateAPIsolation(enabled: Bool) {
        self.isAPIsolationSuspected = enabled
        onStatusChange?()
    }
}
