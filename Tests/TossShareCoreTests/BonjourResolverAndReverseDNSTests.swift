//
//  BonjourResolverAndReverseDNSTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
@testable import TossShareCore

final class BonjourResolverAndReverseDNSTests: XCTestCase {

    func testResolvedEndpointModelAndSorting() {
        let ep1 = NearbyResolvedBonjourEndpoint(host: "fe80::1", port: 44445, isIPv4: false, isLinkLocal: true)
        let ep2 = NearbyResolvedBonjourEndpoint(host: "192.168.1.50", port: 44445, isIPv4: true, isLinkLocal: false)
        let ep3 = NearbyResolvedBonjourEndpoint(host: "10.0.0.1", port: 50000, isIPv4: true, isLinkLocal: false)
        let ep4 = NearbyResolvedBonjourEndpoint(host: "2001:db8::1", port: 44445, isIPv4: false, isLinkLocal: false)

        XCTAssertEqual(ep2.description, "192.168.1.50:44445")
        XCTAssertEqual(ep1.description, "[fe80::1]:44445")

        let unsorted = [ep1, ep2, ep4, ep3]
        let sorted = unsorted.sorted { lhs, rhs in
            if lhs.isIPv4 != rhs.isIPv4 {
                return lhs.isIPv4
            }
            if lhs.isLinkLocal != rhs.isLinkLocal {
                return !lhs.isLinkLocal
            }
            return lhs.description < rhs.description
        }

        // IPv4 harus berada di urutan pertama
        XCTAssertTrue(sorted[0].isIPv4)
        XCTAssertTrue(sorted[1].isIPv4)
        // IPv6 non-link-local berikutnya
        XCTAssertFalse(sorted[2].isIPv4)
        XCTAssertFalse(sorted[2].isLinkLocal)
        // Link-local paling terakhir
        XCTAssertTrue(sorted[3].isLinkLocal)
    }

    func testSockaddrParserIPv4() {
        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(44445).bigEndian
        inet_pton(AF_INET, "192.168.1.123", &addr.sin_addr)

        let data = Data(bytes: &addr, count: MemoryLayout<sockaddr_in>.size)
        let parsed = NearbyBonjourServiceResolver.parseSockaddr(data: data)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.host, "192.168.1.123")
        XCTAssertEqual(parsed?.port, 44445)
        XCTAssertEqual(parsed?.isIPv4, true)
        XCTAssertEqual(parsed?.isLinkLocal, false)
    }

    func testNearbyHostLookupValidation() {
        // IP tidak valid harus menghasilkan nil
        XCTAssertNil(NearbyHostLookup.hostname(forIPv4: ""))
        XCTAssertNil(NearbyHostLookup.hostname(forIPv4: "mDNS"))
        XCTAssertNil(NearbyHostLookup.hostname(forIPv4: "999.999.999.999"))
        XCTAssertNil(NearbyHostLookup.hostname(forIPv4: "not_an_ip"))

        // IP loopback 127.0.0.1 biasanya menghasilkan localhost atau nama mesin
        if let host = NearbyHostLookup.hostname(forIPv4: "127.0.0.1") {
            XCTAssertFalse(host.isEmpty)
            XCTAssertFalse(host.hasSuffix(".local"))
        }
    }

    @MainActor
    func testDeviceRegistryUpdateResolvedEndpoint() {
        let registry = DeviceRegistry(staleThreshold: 60.0, startTimer: false)
        let initialDevice = PeerDevice(
            endpointId: "samsung_a54_test",
            friendlyName: "Samsung Galaxy Phone",
            deviceType: .phone,
            ipAddress: "mDNS",
            port: 0,
            lastSeen: Date(),
            isPrivacyMode: true
        )

        registry.registerOrUpdate(device: initialDevice)
        XCTAssertEqual(registry.devices.count, 1)
        XCTAssertEqual(registry.devices[0].friendlyName, "Samsung Galaxy Phone")
        XCTAssertEqual(registry.devices[0].port, 0)

        // Simulasikan pembaruan hasil resolusi proaktif
        registry.updateResolvedEndpoint(
            endpointId: "samsung_a54_test",
            ip: "192.168.1.100",
            port: 44445,
            hostname: "Galaxy-A54-Bimo"
        )

        XCTAssertEqual(registry.devices[0].ipAddress, "192.168.1.100")
        XCTAssertEqual(registry.devices[0].port, 44445)
        XCTAssertEqual(registry.devices[0].friendlyName, "Galaxy-A54-Bimo")
    }
}
