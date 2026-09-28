//
//  CryptoEngineTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
import CryptoKit
@testable import TossShareCore

final class CryptoEngineTests: XCTestCase {

    func testKeyPairGenerationAndKeyAgreement() throws {
        // Pihak A (Mac) & Pihak B (Samsung)
        let keyA = CryptoEngine.generateP256KeyPair()
        let keyB = CryptoEngine.generateP256KeyPair()

        let pubA = keyA.publicKey.x963Representation
        let pubB = keyB.publicKey.x963Representation

        XCTAssertEqual(pubA.count, 65)
        XCTAssertEqual(pubB.count, 65)

        // Hitung shared secret di kedua sisi
        let secretA = try CryptoEngine.computeSharedSecret(privateKey: keyA, peerPublicKeyData: pubB)
        let secretB = try CryptoEngine.computeSharedSecret(privateKey: keyB, peerPublicKeyData: pubA)

        // Derivasi kunci simetris di kedua sisi dengan salt dan info identik
        let salt = "sample_salt_12345678901234567890".data(using: .utf8)!
        let info = "test_derivation_info".data(using: .utf8)!

        let derivedA = CryptoEngine.deriveKey(from: secretA, salt: salt, info: info, outputByteCount: 32)
        let derivedB = CryptoEngine.deriveKey(from: secretB, salt: salt, info: info, outputByteCount: 32)

        let dataA = derivedA.withUnsafeBytes { Data($0) }
        let dataB = derivedB.withUnsafeBytes { Data($0) }

        XCTAssertEqual(dataA, dataB, "Kunci simetris yang diturunkan kedua belah pihak harus identik.")
    }

    func testAuthPinDerivation() throws {
        let keyA = CryptoEngine.generateP256KeyPair()
        let keyB = CryptoEngine.generateP256KeyPair()

        let secretA = try CryptoEngine.computeSharedSecret(privateKey: keyA, peerPublicKeyData: keyB.publicKey.x963Representation)
        let secretB = try CryptoEngine.computeSharedSecret(privateKey: keyB, peerPublicKeyData: keyA.publicKey.x963Representation)

        let salt = CryptoEngine.secureRandomBytes(count: 32)

        let pinA = CryptoEngine.deriveAuthPin(from: secretA, salt: salt)
        let pinB = CryptoEngine.deriveAuthPin(from: secretB, salt: salt)

        XCTAssertEqual(pinA, pinB, "PIN visual yang dihasilkan kedua belah pihak harus sama persis.")
        XCTAssertEqual(pinA.count, 4, "PIN harus tepat 4 karakter.")
        XCTAssertNotNil(Int(pinA), "PIN harus berupa digit numerik.")
    }

    func testAESGCMEncryptDecryptRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let message = "Halo dari Mac ke Samsung Galaxy!".data(using: .utf8)!

        // Enkripsi
        let ciphertext = try CryptoEngine.encryptAESGCM(plaintext: message, using: key)
        XCTAssertFalse(ciphertext.isEmpty)
        XCTAssertNotEqual(ciphertext, message)

        // Dekripsi
        let decrypted = try CryptoEngine.decryptAESGCM(ciphertextWithNonceAndTag: ciphertext, using: key)
        XCTAssertEqual(decrypted, message)
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), "Halo dari Mac ke Samsung Galaxy!")
    }

    func testAESGCMTamperDetection() throws {
        let key = SymmetricKey(size: .bits256)
        let message = "Payload penting".data(using: .utf8)!

        var ciphertext = try CryptoEngine.encryptAESGCM(plaintext: message, using: key)

        // Rusak 1 byte di payload
        let tamperIndex = ciphertext.count - 5
        ciphertext[tamperIndex] ^= 0xFF

        // Harus gagal saat dekripsi karena tag autentikasi AES-GCM tidak valid
        XCTAssertThrowsError(try CryptoEngine.decryptAESGCM(ciphertextWithNonceAndTag: ciphertext, using: key))
    }

    func testSha256Hex() {
        let emptyData = Data()
        let emptyHash = CryptoEngine.sha256Hex(for: emptyData)
        XCTAssertEqual(emptyHash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

        let testData = "TossShare".data(using: .utf8)!
        let testHash = CryptoEngine.sha256Hex(for: testData)
        XCTAssertFalse(testHash.isEmpty)
        XCTAssertEqual(testHash.count, 64)
    }
}
