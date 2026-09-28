//
//  UKEY2HandshakeTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
import CryptoKit
@testable import TossShareCore

final class UKEY2HandshakeTests: XCTestCase {

    func testFullHandshakeExchange() throws {
        let client = UKEY2Handshake(role: .client)
        let server = UKEY2Handshake(role: .server)

        XCTAssertFalse(client.isCompleted)
        XCTAssertFalse(server.isCompleted)

        // 1. Client membuat ClientInit payload
        let _ = client.makeClientInitPayload()
        XCTAssertEqual(client.state, .clientInitSent)

        // 2. Server menerima ClientInit payload dan mengembalikan ServerInit payload
        let _ = try server.processClientInit(
            clientPublicKeyData: client.localPublicKeyData,
            clientSalt: client.localSalt
        )
        XCTAssertTrue(server.isCompleted)

        // 3. Client memproses ServerInit payload
        try client.processServerInit(
            serverPublicKeyData: server.localPublicKeyData,
            serverSalt: server.localSalt
        )
        XCTAssertTrue(client.isCompleted)

        // 4. Verifikasi kecocokan Auth PIN 4-digit
        guard let clientPIN = client.authPin, let serverPIN = server.authPin else {
            XCTFail("PIN verifikasi visual tidak terdefinisi.")
            return
        }
        XCTAssertEqual(clientPIN, serverPIN, "PIN visual Client dan Server harus identik.")
        XCTAssertEqual(clientPIN.count, 4)

        // 5. Verifikasi kecocokan Kunci Enkripsi dan IV
        XCTAssertNotNil(client.clientKey)
        XCTAssertNotNil(server.clientKey)
        let clientKeyData = client.clientKey!.withUnsafeBytes { Data($0) }
        let serverKeyData = server.clientKey!.withUnsafeBytes { Data($0) }
        XCTAssertEqual(clientKeyData, serverKeyData, "Kunci enkripsi klien harus identik di kedua sisi.")

        let clientServerKeyData = client.serverKey!.withUnsafeBytes { Data($0) }
        let serverServerKeyData = server.serverKey!.withUnsafeBytes { Data($0) }
        XCTAssertEqual(clientServerKeyData, serverServerKeyData, "Kunci enkripsi server harus identik di kedua sisi.")

        XCTAssertEqual(client.clientIV, server.clientIV)
        XCTAssertEqual(client.serverIV, server.serverIV)

        // 6. Uji enkripsi data dari Client dan didekripsi di Server
        let sampleMessage = "Uji coba transfer berkas terenkripsi UKEY2".data(using: .utf8)!
        let encrypted = try CryptoEngine.encryptAESGCM(plaintext: sampleMessage, using: client.clientKey!)
        let decrypted = try CryptoEngine.decryptAESGCM(ciphertextWithNonceAndTag: encrypted, using: server.clientKey!)
        XCTAssertEqual(decrypted, sampleMessage)
    }

    func testInvalidHandshakeSequence() {
        let client = UKEY2Handshake(role: .client)
        let dummyKey = CryptoEngine.generateP256KeyPair().publicKey.x963Representation
        let dummySalt = CryptoEngine.secureRandomBytes(count: 32)

        // Mencoba processServerInit tanpa makeClientInitPayload terlebih dahulu -> Harusnya gagal
        XCTAssertThrowsError(try client.processServerInit(serverPublicKeyData: dummyKey, serverSalt: dummySalt))
    }
}
