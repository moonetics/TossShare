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

    func testQuickShareProtocolEngineKeepAliveAndFileChunkFrames() throws {
        let senderEngine = QuickShareProtocolEngine(role: .sender)
        let receiverEngine = QuickShareProtocolEngine(role: .receiver)

        // 1. Handshake UKEY2 antar engine
        let clientInitData = try senderEngine.makeUkey2ClientInitFrame()
        let serverInitData = try receiverEngine.processUkey2ClientInit(clientInitRawData: clientInitData)
        try senderEngine.processUkey2ServerInit(serverInitRawData: serverInitData)
        try receiverEngine.processUkey2ClientFinish(clientFinishRawData: senderEngine.ukeyClientFinishData!)

        XCTAssertEqual(senderEngine.authPin, receiverEngine.authPin)

        // 2. Uji enkripsi dan dekripsi Keep-Alive Frame (ack: false)
        let keepAliveRaw = try senderEngine.makeKeepAliveFrame(ack: false)
        let decryptedKeepAlive = try receiverEngine.decryptSecureMessage(keepAliveRaw)
        XCTAssertEqual(decryptedKeepAlive.v1.type, .keepAlive)
        XCTAssertFalse(decryptedKeepAlive.v1.keepAlive.ack)

        // 3. Uji enkripsi dan dekripsi Keep-Alive ACK Frame (ack: true)
        let keepAliveAckRaw = try receiverEngine.makeKeepAliveFrame(ack: true)
        let decryptedAck = try senderEngine.decryptSecureMessage(keepAliveAckRaw)
        XCTAssertEqual(decryptedAck.v1.type, .keepAlive)
        XCTAssertTrue(decryptedAck.v1.keepAlive.ack)

        // 4. Uji enkripsi Data Chunk 512KB dengan fileName
        let sampleData = Data(repeating: 0x41, count: 1024)
        let chunkRaw = try senderEngine.makeFileChunkFrame(
            payloadId: 98765,
            totalSize: 100_000,
            offset: 0,
            chunkData: sampleData,
            isLast: false,
            fileName: "laporan_keuangan.pdf"
        )
        let decryptedChunk = try receiverEngine.decryptSecureMessage(chunkRaw)
        XCTAssertEqual(decryptedChunk.v1.type, .payloadTransfer)
        XCTAssertEqual(decryptedChunk.v1.payloadTransfer.payloadChunk.flags, 0)
        XCTAssertEqual(decryptedChunk.v1.payloadTransfer.payloadChunk.body, sampleData)
        XCTAssertEqual(decryptedChunk.v1.payloadTransfer.payloadHeader.fileName, "laporan_keuangan.pdf")

        // 5. Uji sinyal EOF (flags = 1, body kosong, offset = totalSize)
        let eofRaw = try senderEngine.makeFileChunkFrame(
            payloadId: 98765,
            totalSize: 100_000,
            offset: 100_000,
            chunkData: Data(),
            isLast: true,
            fileName: "laporan_keuangan.pdf"
        )
        let decryptedEOF = try receiverEngine.decryptSecureMessage(eofRaw)
        XCTAssertEqual(decryptedEOF.v1.type, .payloadTransfer)
        XCTAssertEqual(decryptedEOF.v1.payloadTransfer.payloadChunk.flags, 1)
        XCTAssertTrue(decryptedEOF.v1.payloadTransfer.payloadChunk.body.isEmpty)
        XCTAssertEqual(decryptedEOF.v1.payloadTransfer.payloadChunk.offset, 100_000)
    }

    func testTwosComplementEncodingAndDecoding() {
        // Kasus 1: Nilai dengan bit 7 aktif (>= 0x80) harus disisipkan 0x00 di depan (33 bytes)
        var highBitData = Data([0x85])
        highBitData.append(Data(repeating: 0x11, count: 31))
        let encodedHigh = QuickShareProtocolEngine.encodeBigEndianTwosComplement(highBitData)
        XCTAssertEqual(encodedHigh.count, 33)
        XCTAssertEqual(encodedHigh[0], 0x00)
        XCTAssertEqual(encodedHigh[1], 0x85)

        // Decode kembali ke 32 bytes
        let decodedHigh = QuickShareProtocolEngine.decodeBigEndianTwosComplementTo32Bytes(encodedHigh)
        XCTAssertEqual(decodedHigh.count, 32)
        XCTAssertEqual(decodedHigh, highBitData)

        // Kasus 2: Nilai dengan bit 7 tidak aktif (< 0x80) tidak disisipkan 0x00 (32 bytes)
        var lowBitData = Data([0x35])
        lowBitData.append(Data(repeating: 0x22, count: 31))
        let encodedLow = QuickShareProtocolEngine.encodeBigEndianTwosComplement(lowBitData)
        XCTAssertEqual(encodedLow.count, 32)
        XCTAssertEqual(encodedLow[0], 0x35)

        let decodedLow = QuickShareProtocolEngine.decodeBigEndianTwosComplementTo32Bytes(encodedLow)
        XCTAssertEqual(decodedLow.count, 32)
        XCTAssertEqual(decodedLow, lowBitData)

        // Kasus 3: Nilai dengan panjang < 32 bytes (misal 30 bytes) di-padding menjadi 32 bytes
        let shortData = Data(repeating: 0x77, count: 30)
        let decodedShort = QuickShareProtocolEngine.decodeBigEndianTwosComplementTo32Bytes(shortData)
        XCTAssertEqual(decodedShort.count, 32)
        XCTAssertEqual(decodedShort.prefix(2), Data([0x00, 0x00]))
        XCTAssertEqual(decodedShort.suffix(30), shortData)
    }

    func testExtractEndpointIdFromMdnsInstanceName() {
        // String nyata dari Samsung Galaxy A54 pengguna: "I1lKN1L8n14AAA"
        let samsungInstanceName = "I1lKN1L8n14AAA"
        let extractedId = EndpointInfoParser.extractEndpointId(fromMdnsInstanceName: samsungInstanceName)
        XCTAssertEqual(extractedId, "YJ7R")

        // Roundtrip test: generate lalu extract
        let testId = "TEST"
        let instance = EndpointInfoParser.generateMdnsInstanceName(endpointId: testId)
        let roundtripId = EndpointInfoParser.extractEndpointId(fromMdnsInstanceName: instance)
        XCTAssertEqual(roundtripId, testId)
    }
}
