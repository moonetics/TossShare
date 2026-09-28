//
//  ModelSerializationTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
@testable import TossShareCore

final class ModelSerializationTests: XCTestCase {

    // MARK: - Codable & Serialization Tests

    func testPeerDeviceCodable() throws {
        let original = PeerDevice(
            endpointId: "s24u",
            friendlyName: "Galaxy S24 Ultra",
            deviceType: .phone,
            ipAddress: "192.168.1.105",
            port: 44445,
            lastSeen: Date(timeIntervalSince1970: 1700000000),
            rssi: -48
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        XCTAssertFalse(data.isEmpty)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PeerDevice.self, from: data)

        XCTAssertEqual(decoded.endpointId, original.endpointId)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.friendlyName, original.friendlyName)
        XCTAssertEqual(decoded.deviceType, original.deviceType)
        XCTAssertEqual(decoded.ipAddress, original.ipAddress)
        XCTAssertEqual(decoded.port, original.port)
        XCTAssertEqual(decoded.rssi, original.rssi)
        XCTAssertEqual(decoded.lastSeen.timeIntervalSince1970, original.lastSeen.timeIntervalSince1970, accuracy: 0.001)
    }

    func testTransferItemCodable() throws {
        let item = TransferItem(
            itemId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            fileName: "video_dokumen.mp4",
            mimeType: "video/mp4",
            fileSize: 104_857_600,
            localURL: URL(fileURLWithPath: "/tmp/video_dokumen.mp4"),
            sha256Checksum: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TransferItem.self, from: data)

        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.fileName, item.fileName)
        XCTAssertEqual(decoded.mimeType, item.mimeType)
        XCTAssertEqual(decoded.fileSize, item.fileSize)
        XCTAssertEqual(decoded.localURL, item.localURL)
        XCTAssertEqual(decoded.sha256Checksum, item.sha256Checksum)
    }

    func testTransferSessionCodable() throws {
        let session = TransferSession(
            sessionId: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            peerEndpointId: "s24u",
            direction: .outgoing,
            state: .transferring,
            authPin: "3194",
            startTime: Date(timeIntervalSince1970: 1700000000),
            totalBytes: 200_000_000,
            transferredBytes: 100_000_000,
            speedBytesPerSecond: 25_000_000,
            items: [
                TransferItem(fileName: "arsip.zip", mimeType: "application/zip", fileSize: 200_000_000)
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TransferSession.self, from: data)

        XCTAssertEqual(decoded.sessionId, session.sessionId)
        XCTAssertEqual(decoded.peerEndpointId, session.peerEndpointId)
        XCTAssertEqual(decoded.direction, session.direction)
        XCTAssertEqual(decoded.state, session.state)
        XCTAssertEqual(decoded.authPin, session.authPin)
        XCTAssertEqual(decoded.totalBytes, session.totalBytes)
        XCTAssertEqual(decoded.transferredBytes, session.transferredBytes)
        XCTAssertEqual(decoded.speedBytesPerSecond, session.speedBytesPerSecond)
        XCTAssertEqual(decoded.progress, 0.5, accuracy: 0.001)
        XCTAssertFalse(decoded.isCompleted)
        XCTAssertEqual(decoded.items.count, 1)
    }

    // MARK: - State Machine Transition Tests

    func testValidStateMachineTransitions() throws {
        var session = TransferSession(
            peerEndpointId: "s24u",
            direction: .outgoing,
            state: .idle,
            totalBytes: 50_000_000
        )

        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.state.isTerminal)

        // 1. idle -> connecting
        try session.transition(to: .connecting)
        XCTAssertEqual(session.state, .connecting)

        // 2. connecting -> authenticating
        try session.transition(to: .authenticating)
        XCTAssertEqual(session.state, .authenticating)

        // 3. authenticating -> waitingAcceptance
        try session.transition(to: .waitingAcceptance)
        XCTAssertEqual(session.state, .waitingAcceptance)

        // 4. waitingAcceptance -> transferring
        try session.transition(to: .transferring)
        XCTAssertEqual(session.state, .transferring)
        XCTAssertNotNil(session.startTime, "startTime harus otomatis terisi saat transfer dimulai.")

        // 5. transferring -> completed
        try session.transition(to: .completed)
        XCTAssertEqual(session.state, .completed)
        XCTAssertTrue(session.isCompleted)
        XCTAssertTrue(session.state.isTerminal)
        XCTAssertNotNil(session.endTime, "endTime harus otomatis terisi saat transfer mencapai status terminal.")
    }

    func testCancellationFromActiveStates() throws {
        // Test cancel dari idle
        var session1 = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .idle)
        try session1.transition(to: .cancelled)
        XCTAssertEqual(session1.state, .cancelled)
        XCTAssertTrue(session1.state.isTerminal)

        // Test cancel dari connecting
        var session2 = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .connecting)
        try session2.transition(to: .cancelled)
        XCTAssertEqual(session2.state, .cancelled)

        // Test cancel dari authenticating
        var session3 = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .authenticating)
        try session3.transition(to: .cancelled)
        XCTAssertEqual(session3.state, .cancelled)

        // Test cancel dari waitingAcceptance
        var session4 = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .waitingAcceptance)
        try session4.transition(to: .cancelled)
        XCTAssertEqual(session4.state, .cancelled)

        // Test cancel dari transferring
        var session5 = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .transferring)
        try session5.transition(to: .cancelled)
        XCTAssertEqual(session5.state, .cancelled)
    }

    func testFailureTransition() {
        var session = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .connecting)
        session.fail(with: "Koneksi ditolak oleh target.")

        XCTAssertEqual(session.state, .failed)
        XCTAssertEqual(session.errorMessage, "Koneksi ditolak oleh target.")
        XCTAssertTrue(session.state.isTerminal)
    }

    func testInvalidStateMachineTransitions() {
        var session = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .idle)

        // Loncat dari idle langsung ke completed -> Ilegal
        XCTAssertThrowsError(try session.transition(to: .completed)) { error in
            XCTAssertEqual(error as? TransferStateError, .invalidTransition(from: .idle, to: .completed))
        }

        // Loncat dari idle langsung ke transferring -> Ilegal
        XCTAssertThrowsError(try session.transition(to: .transferring)) { error in
            XCTAssertEqual(error as? TransferStateError, .invalidTransition(from: .idle, to: .transferring))
        }

        // Loncat dari idle langsung ke authenticating -> Ilegal
        XCTAssertThrowsError(try session.transition(to: .authenticating)) { error in
            XCTAssertEqual(error as? TransferStateError, .invalidTransition(from: .idle, to: .authenticating))
        }
    }

    func testTerminalStateImmutability() throws {
        // completed
        var completedSession = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .transferring)
        try completedSession.transition(to: .completed)

        XCTAssertThrowsError(try completedSession.transition(to: .connecting)) { error in
            XCTAssertEqual(error as? TransferStateError, .sessionAlreadyTerminal(.completed))
        }

        // failed
        var failedSession = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .connecting)
        failedSession.fail(with: "Error jaringan")

        XCTAssertThrowsError(try failedSession.transition(to: .idle)) { error in
            XCTAssertEqual(error as? TransferStateError, .sessionAlreadyTerminal(.failed))
        }

        // cancelled
        var cancelledSession = TransferSession(peerEndpointId: "s24u", direction: .outgoing, state: .idle)
        try cancelledSession.transition(to: .cancelled)

        XCTAssertThrowsError(try cancelledSession.transition(to: .transferring)) { error in
            XCTAssertEqual(error as? TransferStateError, .sessionAlreadyTerminal(.cancelled))
        }
    }

    // MARK: - Progress & Helper Tests

    func testProgressComputation() {
        var session = TransferSession(
            peerEndpointId: "s24u",
            direction: .outgoing,
            state: .transferring,
            totalBytes: 1000,
            transferredBytes: 250
        )
        XCTAssertEqual(session.progress, 0.25, accuracy: 0.001)

        session.updateProgress(transferredBytes: 1000, speedBytesPerSecond: 10_000_000)
        XCTAssertEqual(session.progress, 1.0, accuracy: 0.001)

        // Zero totalBytes tidak boleh divide-by-zero crash
        let emptySession = TransferSession(peerEndpointId: "s24u", direction: .outgoing, totalBytes: 0)
        XCTAssertEqual(emptySession.progress, 0.0)
    }

    // MARK: - Mock Device Seeder Integrity

    func testMockDeviceSeederIntegrity() {
        XCTAssertEqual(MockDeviceSeeder.defaultPeers.count, 3)
        XCTAssertEqual(MockDeviceSeeder.weakSignalPeer.rssi, -88)
        XCTAssertEqual(MockDeviceSeeder.apIsolatedPeer.ipAddress, "10.0.0.45")

        let transferring = MockDeviceSeeder.makeTransferringSession()
        XCTAssertEqual(transferring.state, .transferring)
        XCTAssertEqual(transferring.items.count, 1)
        XCTAssertGreaterThan(transferring.progress, 0.6)
        XCTAssertEqual(transferring.authPin, "4821")

        let completed = MockDeviceSeeder.makeCompletedSession()
        XCTAssertEqual(completed.state, .completed)
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.progress, 1.0)
        XCTAssertEqual(completed.authPin, "9012")
    }
}
