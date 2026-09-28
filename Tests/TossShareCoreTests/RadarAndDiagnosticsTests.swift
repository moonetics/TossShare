//
//  RadarAndDiagnosticsTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
@testable import TossShareCore
@testable import TossShareUI

final class RadarAndDiagnosticsTests: XCTestCase {

    // MARK: - RadarLayoutEngine Geometry Tests

    func testRadarLayoutEngineEmptyDevices() {
        let center = CGPoint(x: 200, y: 200)
        let positions = RadarLayoutEngine.computePositions(for: [], center: center)
        XCTAssertTrue(positions.isEmpty)
    }

    func testRadarLayoutEngineSingleDevice() {
        let center = CGPoint(x: 300, y: 300)
        let device = PeerDevice(
            endpointId: "single_dev",
            friendlyName: "Galaxy S24",
            deviceType: .phone,
            ipAddress: "192.168.1.10",
            port: 44445,
            rssi: -35 // Sangat dekat -> innerRadius
        )

        let positions = RadarLayoutEngine.computePositions(
            for: [device],
            center: center,
            innerRadius: 100,
            outerRadius: 200
        )

        XCTAssertEqual(positions.count, 1)
        let node = positions[0]
        XCTAssertEqual(node.endpointId, "single_dev")
        XCTAssertEqual(node.radius, 100, accuracy: 0.1) // Inner radius
        XCTAssertEqual(node.angle, -.pi / 2, accuracy: 0.01) // Puncak atas (12 o'clock)
        XCTAssertEqual(node.point.x, 300, accuracy: 0.1)
        XCTAssertEqual(node.point.y, 200, accuracy: 0.1) // 300 - 100
    }

    func testRadarLayoutEngineProximityRadiusMapping() {
        let center = CGPoint(x: 250, y: 250)
        let closeDevice = PeerDevice(
            endpointId: "close",
            friendlyName: "Dekat",
            deviceType: .phone,
            ipAddress: "192.168.1.1",
            port: 44445,
            rssi: -35
        )
        let farDevice = PeerDevice(
            endpointId: "far",
            friendlyName: "Jauh",
            deviceType: .phone,
            ipAddress: "192.168.1.2",
            port: 44445,
            rssi: -90
        )

        let positions = RadarLayoutEngine.computePositions(
            for: [closeDevice, farDevice],
            center: center,
            innerRadius: 100,
            outerRadius: 200
        )

        XCTAssertEqual(positions.count, 2)
        let closeNode = positions.first(where: { $0.endpointId == "close" })!
        let farNode = positions.first(where: { $0.endpointId == "far" })!

        XCTAssertEqual(closeNode.radius, 100, accuracy: 0.1)
        XCTAssertEqual(farNode.radius, 200, accuracy: 0.1)
        XCTAssertLessThan(closeNode.radius, farNode.radius)
    }

    func testRadarLayoutEngineAngularDistribution() {
        let center = CGPoint(x: 200, y: 200)
        let devices = (1...4).map { i in
            PeerDevice(
                endpointId: "dev_\(i)",
                friendlyName: "Galaxy \(i)",
                deviceType: .phone,
                ipAddress: "192.168.1.\(i)",
                port: 44445
            )
        }

        let positions = RadarLayoutEngine.computePositions(for: devices, center: center)
        XCTAssertEqual(positions.count, 4)

        // Verifikasi selisih sudut antar node berurutan adalah pi/2 (90 derajat)
        let angleDelta = positions[1].angle - positions[0].angle
        XCTAssertEqual(angleDelta, .pi / 2, accuracy: 0.01)
    }

    // MARK: - Diagnostics & ConnectivityAdvisor Tests

    @MainActor
    func testNetworkHealthMonitorAndAdvisor() {
        let monitor = NetworkHealthMonitor()
        let advisor = ConnectivityAdvisor(healthMonitor: monitor)

        // Kondisi awal normal
        XCTAssertFalse(monitor.isAPIsolationSuspected)
        XCTAssertFalse(advisor.shouldShowFallbackCard)

        // 1. Simulasikan AP Isolation aktif
        advisor.simulateAPIsolation(enabled: true)
        XCTAssertTrue(monitor.isAPIsolationSuspected)
        XCTAssertTrue(advisor.shouldShowFallbackCard)
        XCTAssertEqual(advisor.recommendedFallbackMode, .mobileHotspot)

        // 2. Tutup kartu fallback
        advisor.dismissFallbackCard()
        XCTAssertFalse(advisor.shouldShowFallbackCard)

        // 3. Matikan simulasi
        advisor.simulateAPIsolation(enabled: false)
        XCTAssertFalse(monitor.isAPIsolationSuspected)
        XCTAssertFalse(advisor.shouldShowFallbackCard)
    }

    func testTCPConnectionFailureTriggersAPIsolation() {
        let monitor = NetworkHealthMonitor()
        XCTAssertFalse(monitor.isAPIsolationSuspected)

        // Gagal sekali
        monitor.reportTCPConnectionFailure()
        XCTAssertFalse(monitor.isAPIsolationSuspected)

        // Gagal kedua kali -> AP Isolation suspected
        monitor.reportTCPConnectionFailure()
        XCTAssertTrue(monitor.isAPIsolationSuspected)

        // Reset
        monitor.resetDiagnostics()
        XCTAssertFalse(monitor.isAPIsolationSuspected)
    }

    // MARK: - Deduplication & Disambiguation Tests

    @MainActor
    func testDeviceRegistryIPDeduplication() {
        let registry = DeviceRegistry()

        // Samsung Galaxy memancarkan instance mDNS pertama
        let dev1 = PeerDevice(
            endpointId: "ep_inst1",
            friendlyName: "Samsung Galaxy",
            deviceType: .phone,
            ipAddress: "192.168.1.100",
            port: 44445
        )
        registry.registerOrUpdate(device: dev1)
        XCTAssertEqual(registry.devices.count, 1)
        XCTAssertEqual(registry.devices.first?.endpointId, "ep_inst1")

        // Samsung Galaxy memancarkan instance mDNS baru (ephemeral instance name) dengan IP sama
        let dev2 = PeerDevice(
            endpointId: "ep_inst2",
            friendlyName: "Samsung Galaxy",
            deviceType: .phone,
            ipAddress: "192.168.1.100",
            port: 44445
        )
        registry.registerOrUpdate(device: dev2)

        // Harus tetap 1 perangkat, bukan duplikat 2 avatar di Radar!
        XCTAssertEqual(registry.devices.count, 1)
        XCTAssertEqual(registry.devices.first?.endpointId, "ep_inst2")
    }

    @MainActor
    func testDeviceRegistryNameDisambiguation() {
        let registry = DeviceRegistry()

        let devA = PeerDevice(
            endpointId: "ep_A",
            friendlyName: "Samsung Galaxy",
            deviceType: .phone,
            ipAddress: "192.168.1.100",
            port: 44445
        )
        let devB = PeerDevice(
            endpointId: "ep_B",
            friendlyName: "Samsung Galaxy",
            deviceType: .phone,
            ipAddress: "192.168.1.105",
            port: 44445
        )
        let devC = PeerDevice(
            endpointId: "ep_C",
            friendlyName: "Galaxy Z Fold 6",
            deviceType: .phone,
            ipAddress: "192.168.1.200",
            port: 44445
        )

        registry.registerOrUpdate(device: devA)
        registry.registerOrUpdate(device: devB)
        registry.registerOrUpdate(device: devC)

        XCTAssertEqual(registry.devices.count, 3)

        // devA & devB memiliki nama yang sama, sehingga harus memiliki suffix IP untuk diferensiasi
        XCTAssertEqual(registry.displayName(for: devA), "Samsung Galaxy • .100")
        XCTAssertEqual(registry.displayName(for: devB), "Samsung Galaxy • .105")

        // devC namanya unik, tidak perlu suffix IP
        XCTAssertEqual(registry.displayName(for: devC), "Galaxy Z Fold 6")
    }

    @MainActor
    func testDeviceRegistryPrivacyModeDisplayName() {
        let registry = DeviceRegistry()
        let privacyDev = PeerDevice(
            endpointId: "ep_priv",
            friendlyName: "Samsung Galaxy Phone",
            deviceType: .phone,
            ipAddress: "192.168.1.88",
            port: 44445,
            isPrivacyMode: true
        )
        registry.registerOrUpdate(device: privacyDev)

        // Dalam mode privasi, selalu tampilkan akhiran IP agar pengguna dapat membedakan perangkat
        XCTAssertEqual(registry.displayName(for: privacyDev), "Samsung Galaxy Phone • .88")
    }

    func testQRPairingLocalIPResolution() {
        let ip = QRPairingSheetView.getLocalIPAddress()
        if let ip = ip {
            XCTAssertFalse(ip.isEmpty)
            XCTAssertTrue(ip.contains(".") || ip.contains(":"))
        }
    }
}


