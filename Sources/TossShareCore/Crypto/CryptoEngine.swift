//
//  CryptoEngine.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import CryptoKit
import Security

/// Mesin kriptografi terpadu berbasis Apple CryptoKit murni untuk protokol UKEY2 dan AES-GCM.
public struct CryptoEngine: Sendable {

    // MARK: - Key Generation & Key Agreement (Curve P-256 ECDH)

    /// Membangkitkan pasangan kunci privat & publik NIST P-256 (secp256r1) baru.
    public static func generateP256KeyPair() -> P256.KeyAgreement.PrivateKey {
        return P256.KeyAgreement.PrivateKey()
    }

    /// Menghitung ECDH Shared Secret dari kunci privat lokal dan kunci publik peer.
    public static func computeSharedSecret(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKeyData: Data
    ) throws -> SharedSecret {
        let peerKey: P256.KeyAgreement.PublicKey
        if peerPublicKeyData.count == 65 {
            // ANSI X9.63 uncompressed (0x04 || X || Y)
            peerKey = try P256.KeyAgreement.PublicKey(x963Representation: peerPublicKeyData)
        } else if peerPublicKeyData.count == 64 {
            // Raw representation (X || Y)
            peerKey = try P256.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)
        } else {
            throw CryptoEngineError.invalidPublicKeyLength(peerPublicKeyData.count)
        }
        return try privateKey.sharedSecretFromKeyAgreement(with: peerKey)
    }

    // MARK: - Key Derivation (HKDF-SHA256)

    /// Menurunkan kunci simetris dari Shared Secret menggunakan HKDF-SHA256.
    public static func deriveKey(
        from sharedSecret: SharedSecret,
        salt: Data,
        info: Data,
        outputByteCount: Int = 32
    ) -> SymmetricKey {
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: outputByteCount
        )
    }

    /// Menghitung representasi token PIN 4-digit visual untuk konfirmasi UI pengguna.
    /// Format: Angka 1000 - 9999 yang diturunkan dari token otentikasi HKDF.
    public static func deriveAuthPin(from sharedSecret: SharedSecret, salt: Data) -> String {
        let authInfo = "UKEY2 auth token".data(using: .utf8) ?? Data()
        let authKey = deriveKey(from: sharedSecret, salt: salt, info: authInfo, outputByteCount: 32)
        let keyData = authKey.withUnsafeBytes { Data($0) }
        
        // Ambil 4 byte pertama sebagai integer big-endian
        let rawInt = keyData.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let pinNumber = (Int64(rawInt) % 9000) + 1000
        return String(format: "%04lld", pinNumber)
    }

    // MARK: - Enkripsi & Dekripsi Simetris (AES-GCM)

    /// Mengenkripsi payload biner menggunakan AES-GCM dengan kunci simetris dan nonce 12-byte.
    public static func encryptAESGCM(
        plaintext: Data,
        using key: SymmetricKey,
        nonce: AES.GCM.Nonce? = nil
    ) throws -> Data {
        let sealedBox: AES.GCM.SealedBox
        if let nonce = nonce {
            sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        } else {
            sealedBox = try AES.GCM.seal(plaintext, using: key)
        }
        guard let combined = sealedBox.combined else {
            throw CryptoEngineError.encryptionFailed
        }
        return combined
    }

    /// Mendekripsi payload AES-GCM (format combined: Nonce [12] + Ciphertext + Tag [16]).
    public static func decryptAESGCM(
        ciphertextWithNonceAndTag: Data,
        using key: SymmetricKey
    ) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertextWithNonceAndTag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Utilitas Keamanan

    /// Membangkitkan n byte acak yang aman secara kriptografi.
    public static func secureRandomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        // Fallback aman menggunakan CryptoKit SymmetricKey
        let key = SymmetricKey(size: .init(bitCount: count * 8))
        return key.withUnsafeBytes { Data($0) }
    }

    /// Menghitung SHA-256 digest dari suatu data biner (format hex string).
    public static func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Error yang dapat terjadi selama operasi kriptografi.
public enum CryptoEngineError: Error, Equatable, Sendable {
    case invalidPublicKeyLength(Int)
    case encryptionFailed
    case decryptionFailed
}
