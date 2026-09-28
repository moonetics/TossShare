//
//  EndpointInfoParsingTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
@testable import TossShareCore

final class EndpointInfoParsingTests: XCTestCase {

    func testPhoneEndpointParsing() throws {
        let expectedName = "Galaxy S24 Ultra"
        let salt = "1234567890abcdef".data(using: .utf8)!

        let nRecord = EndpointInfoParser.createRecord(
            friendlyName: expectedName,
            deviceType: .phone,
            salt: salt
        )

        let parsed = try EndpointInfoParser.parse(nRecord: nRecord)
        XCTAssertEqual(parsed.friendlyName, expectedName)
        XCTAssertEqual(parsed.deviceType, .phone)
        XCTAssertEqual(parsed.salt, salt)
    }

    func testTabletEndpointParsing() throws {
        let expectedName = "Galaxy Tab S9+"
        let nRecord = EndpointInfoParser.createRecord(
            friendlyName: expectedName,
            deviceType: .tablet
        )

        let parsed = try EndpointInfoParser.parse(nRecord: nRecord)
        XCTAssertEqual(parsed.friendlyName, expectedName)
        XCTAssertEqual(parsed.deviceType, .tablet)
        XCTAssertEqual(parsed.salt.count, 16)
    }

    func testLaptopEndpointParsing() throws {
        let expectedName = "Galaxy Book4 Pro"
        let nRecord = EndpointInfoParser.createRecord(
            friendlyName: expectedName,
            deviceType: .laptop
        )

        let parsed = try EndpointInfoParser.parse(nRecord: nRecord)
        XCTAssertEqual(parsed.friendlyName, expectedName)
        XCTAssertEqual(parsed.deviceType, .laptop)
    }

    func testInvalidBase64Record() {
        let invalidRecord = "!!! Bukan Base64 Yang Valid !!!"
        XCTAssertThrowsError(try EndpointInfoParser.parse(nRecord: invalidRecord)) { error in
            XCTAssertEqual(error as? EndpointInfoParseError, .invalidBase64Encoding)
        }
    }

    func testTooShortPayload() {
        let shortData = Data([0x02, 0x01, 0x02, 0x03]) // Hanya 4 bytes (< 18 bytes)
        XCTAssertThrowsError(try EndpointInfoParser.parse(data: shortData)) { error in
            XCTAssertEqual(error as? EndpointInfoParseError, .payloadTooShort(4))
        }
    }

    @MainActor
    func testDeviceRegistryOperations() {
        let registry = DeviceRegistry(staleThreshold: 2.0, startTimer: false)
        XCTAssertTrue(registry.devices.isEmpty)

        // 1. Register device baru
        let peer1 = PeerDevice(
            endpointId: "s24u",
            friendlyName: "Galaxy S24 Ultra",
            deviceType: .phone,
            ipAddress: "192.168.1.105",
            port: 44445
        )
        registry.registerOrUpdate(device: peer1)
        XCTAssertEqual(registry.devices.count, 1)
        XCTAssertEqual(registry.devices.first?.friendlyName, "Galaxy S24 Ultra")
        XCTAssertNil(registry.devices.first?.rssi)

        // 2. Update RSSI dari BLE
        registry.updateRSSI(endpointId: "s24u", rssi: -45)
        XCTAssertEqual(registry.devices.first?.rssi, -45)

        // 3. Register device kedua
        let peer2 = PeerDevice(
            endpointId: "tbs9",
            friendlyName: "Galaxy Tab S9",
            deviceType: .tablet,
            ipAddress: "192.168.1.120",
            port: 44445
        )
        registry.registerOrUpdate(device: peer2)
        XCTAssertEqual(registry.devices.count, 2)

        // 4. Remove satu device
        registry.removeDevice(endpointId: "s24u")
        XCTAssertEqual(registry.devices.count, 1)
        XCTAssertEqual(registry.devices.first?.endpointId, "tbs9")

        // 5. Clear all
        registry.clearAll()
        XCTAssertTrue(registry.devices.isEmpty)
    }
}
