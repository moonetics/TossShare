//
//  UKEY2Handshake.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import CryptoKit

/// Mengelola siklus jabat tangan protokol Google UKEY2 (Curve P-256 ECDH + HKDF-SHA256).
public final class UKEY2Handshake: @unchecked Sendable {

    public enum Role: Sendable {
        case client // Pengirim (Mac -> Samsung)
        case server // Penerima (Samsung -> Mac)
    }

    public enum State: Sendable, Equatable {
        case initial
        case clientInitSent
        case serverInitSent
        case completed
        case failed(String)
    }

    public let role: Role
    public private(set) var state: State = .initial

    // Local Cryptographic State
    private let privateKey: P256.KeyAgreement.PrivateKey
    public let localPublicKeyData: Data
    public let localSalt: Data

    // Peer Cryptographic State
    public private(set) var peerPublicKeyData: Data?
    public private(set) var peerSalt: Data?

    // Derived Session Credentials
    public private(set) var authPin: String?
    public private(set) var clientKey: SymmetricKey?
    public private(set) var serverKey: SymmetricKey?
    public private(set) var clientIV: Data?
    public private(set) var serverIV: Data?

    public var isCompleted: Bool {
        state == .completed
    }

    public init(role: Role) {
        self.role = role
        let key = CryptoEngine.generateP256KeyPair()
        self.privateKey = key
        self.localPublicKeyData = key.publicKey.x963Representation
        self.localSalt = CryptoEngine.secureRandomBytes(count: 32)
    }

    // MARK: - Client Role Workflow (Mac Outgoing)

    /// Menghasilkan paket data untuk ClientInit.
    public func makeClientInitPayload() -> Data {
        state = .clientInitSent
        var payload = Data()
        // Format biner sederhana UKEY2: Length(1B) + PublicKey + Length(1B) + Salt
        payload.append(UInt8(localPublicKeyData.count))
        payload.append(localPublicKeyData)
        payload.append(UInt8(localSalt.count))
        payload.append(localSalt)
        return payload
    }

    /// Memproses respon ServerInit dari Samsung Galaxy target.
    public func processServerInit(serverPublicKeyData: Data, serverSalt: Data) throws {
        guard state == .clientInitSent else {
            throw UKEY2Error.invalidState("Harus mengirim ClientInit terlebih dahulu.")
        }
        self.peerPublicKeyData = serverPublicKeyData
        self.peerSalt = serverSalt

        try deriveSessionKeys(
            clientPublicKey: localPublicKeyData,
            serverPublicKey: serverPublicKeyData,
            clientSalt: localSalt,
            serverSalt: serverSalt
        )
        self.state = .completed
    }

    // MARK: - Server Role Workflow (Mac Incoming / Receiver)

    /// Memproses inisiasi ClientInit dari perangkat Samsung yang mengirim file ke Mac.
    public func processClientInit(clientPublicKeyData: Data, clientSalt: Data) throws -> Data {
        guard state == .initial else {
            throw UKEY2Error.invalidState("Server handshake telah dimulai sebelumnya.")
        }
        self.peerPublicKeyData = clientPublicKeyData
        self.peerSalt = clientSalt

        try deriveSessionKeys(
            clientPublicKey: clientPublicKeyData,
            serverPublicKey: localPublicKeyData,
            clientSalt: clientSalt,
            serverSalt: localSalt
        )
        self.state = .completed

        // Kembalikan ServerInit payload
        var response = Data()
        response.append(UInt8(localPublicKeyData.count))
        response.append(localPublicKeyData)
        response.append(UInt8(localSalt.count))
        response.append(localSalt)
        return response
    }

    // MARK: - Key Derivation

    private func deriveSessionKeys(
        clientPublicKey: Data,
        serverPublicKey: Data,
        clientSalt: Data,
        serverSalt: Data
    ) throws {
        guard let peerPubKey = peerPublicKeyData else {
            throw UKEY2Error.missingPeerKey
        }

        let sharedSecret = try CryptoEngine.computeSharedSecret(
            privateKey: privateKey,
            peerPublicKeyData: peerPubKey
        )

        // Gabungan salt: clientSalt (32) + serverSalt (32)
        var combinedSalt = Data()
        combinedSalt.append(clientSalt)
        combinedSalt.append(serverSalt)

        // 1. Derivasi 4-digit Auth PIN untuk verifikasi visual
        self.authPin = CryptoEngine.deriveAuthPin(from: sharedSecret, salt: combinedSalt)

        // 2. Derivasi Kunci Enkripsi AES-GCM Client & Server
        let clientKeyInfo = "client_key".data(using: .utf8) ?? Data()
        let serverKeyInfo = "server_key".data(using: .utf8) ?? Data()
        let clientIVInfo  = "client_iv".data(using: .utf8) ?? Data()
        let serverIVInfo  = "server_iv".data(using: .utf8) ?? Data()

        self.clientKey = CryptoEngine.deriveKey(from: sharedSecret, salt: combinedSalt, info: clientKeyInfo, outputByteCount: 32)
        self.serverKey = CryptoEngine.deriveKey(from: sharedSecret, salt: combinedSalt, info: serverKeyInfo, outputByteCount: 32)

        let clientIVKey = CryptoEngine.deriveKey(from: sharedSecret, salt: combinedSalt, info: clientIVInfo, outputByteCount: 12)
        let serverIVKey = CryptoEngine.deriveKey(from: sharedSecret, salt: combinedSalt, info: serverIVInfo, outputByteCount: 12)

        self.clientIV = clientIVKey.withUnsafeBytes { Data($0) }
        self.serverIV = serverIVKey.withUnsafeBytes { Data($0) }
    }
}

public enum UKEY2Error: Error, Equatable, Sendable {
    case invalidState(String)
    case missingPeerKey
    case handshakeFailed(String)
}
