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
        let shortData = Data([0x02, 0x01, 0x02, 0x03]) // Hanya 4 bytes (< 17 bytes)
        XCTAssertThrowsError(try EndpointInfoParser.parse(data: shortData)) { error in
            XCTAssertEqual(error as? EndpointInfoParseError, .payloadTooShort(4))
        }
    }

    func testSamsungQuickSharePrivacyMode17Bytes() throws {
        // Format privasi Samsung: 1 byte bitfield + 16 bytes salt (total 17 bytes)
        var payload = Data([0x02]) // Phone type
        let dummySalt = Data(repeating: 0xAA, count: 16)
        payload.append(dummySalt)
        XCTAssertEqual(payload.count, 17)

        let parsed = try EndpointInfoParser.parse(data: payload)
        XCTAssertEqual(parsed.friendlyName, "Samsung Galaxy Phone")
        XCTAssertTrue(parsed.isPrivacyMode)
        XCTAssertEqual(parsed.deviceType, .phone)
        XCTAssertEqual(parsed.salt, dummySalt)
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

    func testGenerateMdnsInstanceName() {
        let epId = "ZK7J"
        let instanceName = EndpointInfoParser.generateMdnsInstanceName(endpointId: epId)
        XCTAssertFalse(instanceName.contains("="))
        XCTAssertFalse(instanceName.contains("+"))
        XCTAssertFalse(instanceName.contains("/"))

        // Decode Base64
        var base64 = instanceName.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else {
            XCTFail("Failed to decode base64 instance name")
            return
        }

        XCTAssertEqual(data.count, 10)
        XCTAssertEqual(data[0], 0x23) // PCP byte
        let ep = String(data: data.subdata(in: 1..<5), encoding: .utf8)
        XCTAssertEqual(ep, epId)
        XCTAssertEqual(data[5], 0xFC)
        XCTAssertEqual(data[6], 0x9F)
        XCTAssertEqual(data[7], 0x5E)
        XCTAssertEqual(data[8], 0x00)
        XCTAssertEqual(data[9], 0x00)
    }

    @MainActor
    func testDeviceRegistryDynamicFriendlyNameUpdate() {
        let registry = DeviceRegistry(staleThreshold: 60.0, startTimer: false)
        let peer = PeerDevice(
            endpointId: "ep123",
            friendlyName: "Samsung Galaxy",
            deviceType: .phone,
            ipAddress: "192.168.1.55",
            port: 53600,
            isPrivacyMode: true
        )
        registry.registerOrUpdate(device: peer)

        // Update via endpointId
        registry.updateFriendlyName(forEndpointId: "ep123", friendlyName: "Galaxy A54 5G")
        XCTAssertEqual(registry.devices.first?.friendlyName, "Galaxy A54 5G")
        XCTAssertFalse(registry.devices.first?.isPrivacyMode ?? true)

        // Update via IP
        registry.updateFriendlyName(forIP: "192.168.1.55", friendlyName: "Bimo's A54")
        XCTAssertEqual(registry.devices.first?.friendlyName, "Bimo's A54")
    }

    func testSenderSessionErrorLocalizedDescriptions() {
        let err4 = SenderSessionError.invalidHandshakePayload
        XCTAssertEqual(err4.errorDescription, "Format data jabat tangan tidak valid atau sesi terputus.")

        let errReject = SenderSessionError.transferRejected
        XCTAssertEqual(errReject.errorDescription, "Permintaan transfer ditolak di layar Samsung.")

        let errStorage = SenderSessionError.storageFull
        XCTAssertEqual(errStorage.errorDescription, "Ruang penyimpanan ponsel tujuan tidak mencukupi.")

        let errTimeout = SenderSessionError.transferTimedOut
        XCTAssertEqual(errTimeout.errorDescription, "Permintaan transfer kedaluwarsa di layar Samsung.")

        let errLock = SenderSessionError.screenLockedOrUnreachable
        XCTAssertTrue(errLock.errorDescription?.contains("kunci layar") ?? false)
    }

    func testReceiverServerErrorLocalizedDescriptions() {
        let errPort = ReceiverServerError.invalidPort(0)
        XCTAssertEqual(errPort.errorDescription, "Nomor port server (0) tidak valid.")

        let errPayload = ReceiverServerError.invalidHandshakePayload
        XCTAssertEqual(errPayload.errorDescription, "Format jabat tangan penerima tidak valid atau sesi terputus.")

        let errStorage = ReceiverServerError.storageFull
        XCTAssertEqual(errStorage.errorDescription, "Ruang penyimpanan disk Mac penuh. Tidak dapat menerima berkas.")

        let errTimeout = ReceiverServerError.transferTimedOut
        XCTAssertEqual(errTimeout.errorDescription, "Waktu tunggu sesi penerima kedaluwarsa.")
    }

    func testClipboardTextIntroductionFrame() {
        let (frame, pId) = QuickShareProtocolEngine.makeTextIntroductionFrame(text: "https://github.com", title: "GitHub URL")
        XCTAssertEqual(frame.v1.type, .introduction)
        XCTAssertEqual(frame.v1.introduction.textMetadata.count, 1)
        let meta = frame.v1.introduction.textMetadata[0]
        XCTAssertEqual(meta.payloadID, pId)
        XCTAssertEqual(meta.type, .url)
        XCTAssertEqual(meta.textTitle, "GitHub URL")
    }

    func testSenderSessionClipboardConvenienceInit() {
        let text = "Halo dari TossShare Mac!"
        let session = NearbySenderSession(peerEndpointId: "test_endpoint", clipboardText: text)
        XCTAssertEqual(session.session.peerEndpointId, "test_endpoint")
        XCTAssertEqual(session.session.direction, .outgoing)
        XCTAssertEqual(session.session.items.count, 1)
        XCTAssertEqual(session.session.items.first?.fileName, text)
        XCTAssertEqual(session.session.items.first?.mimeType, "text/plain")
        XCTAssertEqual(session.session.items.first?.fileSize, Int64(text.utf8.count))
        XCTAssertEqual(session.session.totalBytes, Int64(text.utf8.count))
    }

    func testSenderSessionDeviceClipboardInit() {
        let peer = PeerDevice(
            endpointId: "samsung_a54",
            friendlyName: "Galaxy A54",
            deviceType: .phone,
            ipAddress: "192.168.1.50",
            port: 44445
        )
        let text = "https://github.com/leonboe1/QuickDrop"
        let session = NearbySenderSession(device: peer, clipboardText: text)
        XCTAssertEqual(session.targetDevice?.endpointId, "samsung_a54")
        XCTAssertEqual(session.session.peerEndpointId, "samsung_a54")
        XCTAssertEqual(session.session.items.first?.fileName, text)
    }

    func testSenderSessionSendClipboardTextUnreachable() async {
        let session = NearbySenderSession(peerEndpointId: "unknown_endpoint", items: [])
        do {
            try await session.sendClipboardText(text: "Percobaan kirim")
            XCTFail("Harusnya melempar error screenLockedOrUnreachable")
        } catch let err as SenderSessionError {
            XCTAssertEqual(err, .screenLockedOrUnreachable)
            XCTAssertTrue(err.localizedDescription.contains("kunci layar terbuka"))
        } catch {
            XCTFail("Error tidak terduga: \(error)")
        }
    }
}

