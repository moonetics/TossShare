//
//  DeviceRegistry.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import Combine

/// Central Registry reaktif untuk menyimpan dan mengelola daftar perangkat terdeteksi di jaringan lokal.
@MainActor
public final class DeviceRegistry: ObservableObject {
    public static let shared = DeviceRegistry()

    @Published public private(set) var devices: [PeerDevice] = []

    private var cleanupTask: Task<Void, Never>?
    public let staleThreshold: TimeInterval

    public init(staleThreshold: TimeInterval = 60.0, startTimer: Bool = true) {
        self.staleThreshold = staleThreshold
        if startTimer {
            self.startAutoCleanup(interval: 15.0)
        }
    }

    deinit {
        cleanupTask?.cancel()
    }

    // MARK: - Registry Operations

    /// Mendaftarkan atau memperbarui informasi perangkat yang ditemukan dengan deduplikasi cerdas berbasis IP/Host.
    public func registerOrUpdate(device: PeerDevice) {
        // Saring dan tolak instans milik Mac sendiri
        if ActiveServerTracker.shared.isSelf(instanceNameOrEndpointId: device.endpointId) {
            return
        }
        if device.friendlyName.contains("MacBook") || device.friendlyName.contains("TossShare") {
            return
        }
        if device.ipAddress == "127.0.0.1" && ActiveServerTracker.shared.isSelfPort(UInt16(device.port)) {
            return
        }

        let existingIndex = devices.firstIndex(where: {
            $0.endpointId == device.endpointId ||
            (!device.ipAddress.isEmpty && device.ipAddress != "mDNS" && $0.ipAddress == device.ipAddress)
        })

        if let index = existingIndex {
            var updated = devices[index]
            updated.endpointId = device.endpointId

            // Pertahankan nama kustom jika pembaruan baru berada dalam mode privasi
            if !device.isPrivacyMode {
                updated.friendlyName = device.friendlyName
                updated.isPrivacyMode = false
            } else if updated.isPrivacyMode {
                updated.friendlyName = device.friendlyName
                updated.isPrivacyMode = true
            }

            updated.deviceType = device.deviceType
            if !device.ipAddress.isEmpty && device.ipAddress != "mDNS" {
                updated.ipAddress = device.ipAddress
            }
            if device.port > 0 {
                updated.port = device.port
            }
            if let ep = device.endpoint {
                updated.endpoint = ep
            }
            updated.lastSeen = Date()
            if let newRSSI = device.rssi {
                updated.rssi = newRSSI
            }
            devices[index] = updated
        } else {
            var newDevice = device
            newDevice.lastSeen = Date()
            devices.append(newDevice)
        }
    }

    /// Menghasilkan nama tampilan yang membedakan perangkat jika terdapat beberapa perangkat dengan nama identik di jaringan.
    public func displayName(for device: PeerDevice) -> String {
        let sameNameDevices = devices.filter { $0.friendlyName == device.friendlyName }
        let hasIP = !device.ipAddress.isEmpty && device.ipAddress != "mDNS"
        let lastOctet = hasIP ? (device.ipAddress.split(separator: ".").last.map(String.init) ?? device.ipAddress) : ""

        if device.isPrivacyMode && hasIP {
            return "\(device.friendlyName) • .\(lastOctet)"
        }

        if sameNameDevices.count > 1 && hasIP {
            return "\(device.friendlyName) • .\(lastOctet)"
        }
        return device.friendlyName
    }

    /// Memperbarui nilai RSSI kedekatan perangkat tertentu dari pemindaian Bluetooth LE.
    public func updateRSSI(endpointId: String, rssi: Int) {
        if let index = devices.firstIndex(where: { $0.endpointId == endpointId }) {
            var updated = devices[index]
            updated.rssi = rssi
            updated.lastSeen = Date()
            devices[index] = updated
        }
    }

    /// Menghapus perangkat dari daftar (misal saat terdeteksi offline secara eksplisit).
    public func removeDevice(endpointId: String) {
        devices.removeAll { $0.endpointId == endpointId }
    }

    /// Mencari perangkat berdasarkan endpoint ID.
    public func getDevice(byEndpointId endpointId: String) -> PeerDevice? {
        return devices.first(where: { $0.endpointId == endpointId })
    }

    /// Menghapus seluruh perangkat yang tidak lagi mengirimkan beacon dalam kurun waktu `staleThreshold`.
    public func cleanupStaleDevices() {
        let now = Date()
        devices.removeAll { now.timeIntervalSince($0.lastSeen) > staleThreshold }
    }

    /// Menghapus seluruh entri perangkat (misal saat Wi-Fi dimatikan atau reset aplikasi).
    public func clearAll() {
        devices.removeAll()
    }

    /// Memperbarui nama perangkat secara dinamis jika nama asli diperoleh melalui jabat tangan koneksi.
    public func updateFriendlyName(forIP ip: String, friendlyName: String) {
        guard !friendlyName.isEmpty, !ip.isEmpty, ip != "mDNS" else { return }
        if let index = devices.firstIndex(where: { $0.ipAddress == ip }) {
            var updated = devices[index]
            updated.friendlyName = friendlyName
            updated.isPrivacyMode = false
            updated.lastSeen = Date()
            devices[index] = updated
        }
    }

    /// Memperbarui nama perangkat secara dinamis berdasarkan endpointId.
    public func updateFriendlyName(forEndpointId endpointId: String, friendlyName: String) {
        guard !friendlyName.isEmpty, !endpointId.isEmpty else { return }
        if let index = devices.firstIndex(where: { $0.endpointId == endpointId }) {
            var updated = devices[index]
            updated.friendlyName = friendlyName
            updated.isPrivacyMode = false
            updated.lastSeen = Date()
            devices[index] = updated
        }
    }

    /// Memperbarui alamat IP, port riil, dan nama host perangkat yang berhasil di-resolve dari Bonjour & Reverse DNS.
    public func updateResolvedEndpoint(
        endpointId: String,
        ip: String,
        port: UInt16,
        hostname: String? = nil
    ) {
        guard let index = devices.firstIndex(where: { $0.endpointId == endpointId }) else { return }
        var updated = devices[index]
        if !ip.isEmpty && ip != "mDNS" {
            updated.ipAddress = ip
        }
        if port > 0 {
            updated.port = Int(port)
        }
        if let h = hostname, !h.isEmpty {
            if updated.isPrivacyMode {
                updated.friendlyName = h
            }
        }
        updated.lastSeen = Date()
        devices[index] = updated
    }

    // MARK: - Auto-Cleanup Task

    public func startAutoCleanup(interval: TimeInterval = 5.0) {
        cleanupTask?.cancel()
        let nanoseconds = UInt64(interval * 1_000_000_000)
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { break }
                self?.cleanupStaleDevices()
            }
        }
    }

    public func stopAutoCleanup() {
        cleanupTask?.cancel()
        cleanupTask = nil
    }
}
