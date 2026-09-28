//
//  BLEProximityMonitor.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import CoreBluetooth

/// Memindai beacon kedekatan Bluetooth Low Energy (BLE) untuk memperkaya data RSSI perangkat terdekat.
public final class BLEProximityMonitor: NSObject, CBCentralManagerDelegate, @unchecked Sendable {

    public enum Status: Sendable, Equatable {
        case idle
        case scanning
        case bluetoothUnavailable
        case unauthorized
    }

    public private(set) var status: Status = .idle
    private var centralManager: CBCentralManager?
    private weak var registry: DeviceRegistry?
    private let queue = DispatchQueue(label: "com.tossshare.ble.proximity", qos: .utility)

    private let targetServiceUUIDs: [CBUUID] = [
        CBUUID(string: TossShareCore.quickShareServiceUUID), // FE2C
        CBUUID(string: "FC12"),
        CBUUID(string: "FEF3")
    ]

    public init(registry: DeviceRegistry) {
        self.registry = registry
        super.init()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring Control

    /// Memulai pemantauan sinyal BLE.
    public func startMonitoring() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    /// Menghentikan pemantauan sinyal BLE.
    public func stopMonitoring() {
        centralManager?.stopScan()
        centralManager = nil
        status = .idle
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = .scanning
            central.scanForPeripherals(
                withServices: targetServiceUUIDs,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        case .unauthorized:
            status = .unauthorized
        default:
            status = .bluetoothUnavailable
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiValue = RSSI.intValue
        guard rssiValue < 0 && rssiValue > -100 else { return }

        // Cek nama peripheral atau service data untuk menghubungkan dengan endpointId
        if let name = peripheral.name, !name.isEmpty {
            Task { @MainActor [weak self] in
                self?.registry?.updateRSSI(endpointId: name, rssi: rssiValue)
            }
        }
    }
}
