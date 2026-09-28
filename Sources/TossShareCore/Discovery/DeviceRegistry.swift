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

    @Published public private(set) var devices: [PeerDevice] = []

    private var cleanupTask: Task<Void, Never>?
    public let staleThreshold: TimeInterval

    public init(staleThreshold: TimeInterval = 20.0, startTimer: Bool = true) {
        self.staleThreshold = staleThreshold
        if startTimer {
            self.startAutoCleanup()
        }
    }

    deinit {
        cleanupTask?.cancel()
    }

    // MARK: - Registry Operations

    /// Mendaftarkan atau memperbarui informasi perangkat yang ditemukan.
    public func registerOrUpdate(device: PeerDevice) {
        if let index = devices.firstIndex(where: { $0.endpointId == device.endpointId }) {
            var updated = devices[index]
            updated.friendlyName = device.friendlyName
            updated.deviceType = device.deviceType
            updated.ipAddress = device.ipAddress
            updated.port = device.port
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

    /// Menghapus seluruh perangkat yang tidak lagi mengirimkan beacon dalam kurun waktu `staleThreshold`.
    public func cleanupStaleDevices() {
        let now = Date()
        devices.removeAll { now.timeIntervalSince($0.lastSeen) > staleThreshold }
    }

    /// Menghapus seluruh entri perangkat (misal saat Wi-Fi dimatikan atau reset aplikasi).
    public func clearAll() {
        devices.removeAll()
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
