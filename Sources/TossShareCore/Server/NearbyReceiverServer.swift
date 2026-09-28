//
//  NearbyReceiverServer.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import Network
import CryptoKit

/// Server penerima berkas (Samsung -> Mac) berbasis NWListener dengan dukungan UKEY2 dan staging aman.
public final class NearbyReceiverServer: @unchecked Sendable {

    public let port: UInt16
    public let friendlyName: String
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.tossshare.receiver.server", qos: .userInitiated)
    private let fileManager: TransferFileManager

    /// Handler persetujuan penerimaan berkas (memberikan kesempatan pengguna/UI menerima atau menolak).
    public var onRequestAcceptance: (@Sendable (TransferSession) async -> Bool)?
    public var onTransferCompleted: (@Sendable (TransferSession) -> Void)?
    public var onTransferFailed: (@Sendable (TransferSession, Error) -> Void)?

    public init(
        port: UInt16 = 44445,
        friendlyName: String = "Mac (TossShare)",
        fileManager: TransferFileManager = TransferFileManager()
    ) {
        self.port = port
        self.friendlyName = friendlyName
        self.fileManager = fileManager
    }

    deinit {
        stop()
    }

    // MARK: - Server Lifecycle

    /// Membuka server soket TCP lokal dan mendaftarkan layanan mDNS Quick Share.
    public func start() throws {
        guard listener == nil else { return }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ReceiverServerError.invalidPort(Int(port))
        }

        let newListener = try NWListener(using: params, on: nwPort)

        // Konfigurasi Publikasi mDNS Bonjour
        let txtRecord = EndpointInfoParser.createRecord(friendlyName: friendlyName, deviceType: .laptop)
        var bonjourTXT = NWTXTRecord()
        bonjourTXT["n"] = txtRecord
        let bonjourDesc = NWListener.Service(
            type: TossShareCore.quickShareMDNSServiceType,
            txtRecord: bonjourTXT
        )
        newListener.service = bonjourDesc

        newListener.newConnectionHandler = { [weak self] newConnection in
            self?.handleIncomingConnection(newConnection)
        }

        newListener.stateUpdateHandler = { newState in
            switch newState {
            case .failed(let err):
                print("[NearbyReceiverServer] Listener error: \(err)")
            default:
                break
            }
        }

        newListener.start(queue: queue)
        self.listener = newListener
    }

    /// Menghentikan server penerima.
    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handler

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        Task {
            var activeStagingURL: URL?
            do {
                // 1. UKEY2 Handshake: Baca ClientInit
                let clientInitPacket = try await receiveLengthPrefixedData(from: connection)
                guard clientInitPacket.count >= 2 else {
                    throw ReceiverServerError.invalidHandshakePayload
                }

                let pubKeyLen = Int(clientInitPacket[0])
                let pubKeyEnd = 1 + pubKeyLen
                let clientPubKey = clientInitPacket.subdata(in: 1..<pubKeyEnd)

                let saltLen = Int(clientInitPacket[pubKeyEnd])
                let saltEnd = pubKeyEnd + 1 + saltLen
                let clientSalt = clientInitPacket.subdata(in: (pubKeyEnd + 1)..<saltEnd)

                let handshake = UKEY2Handshake(role: .server)
                let serverInitPayload = try handshake.processClientInit(
                    clientPublicKeyData: clientPubKey,
                    clientSalt: clientSalt
                )
                let serverInitPacket = WireEncoding.encodeLengthPrefixed(serverInitPayload)
                try await sendData(serverInitPacket, on: connection)

                guard let pin = handshake.authPin, let clientKey = handshake.clientKey else {
                    throw ReceiverServerError.keyDerivationFailed
                }

                // 2. Baca IntroductionFrame (Manifest Berkas)
                let introPacket = try await receiveLengthPrefixedData(from: connection)
                let (frameType, payload) = try NearbyFrameCodec.decodeTypeAndPayload(from: introPacket)
                guard frameType == .introduction else {
                    throw ReceiverServerError.unexpectedFrame(expected: .introduction, actual: frameType)
                }

                let intro = try NearbyFrameCodec.decodePayload(IntroductionFrame.self, from: payload)
                var session = TransferSession(
                    peerEndpointId: "samsung_client",
                    direction: .incoming,
                    state: .waitingAcceptance,
                    authPin: pin,
                    totalBytes: intro.items.reduce(0) { $0 + $1.fileSize },
                    items: intro.items
                )

                // 3. Konfirmasi Penerimaan (Acceptance Prompt)
                let isAccepted: Bool
                if let acceptanceHandler = onRequestAcceptance {
                    isAccepted = await acceptanceHandler(session)
                } else {
                    isAccepted = true // Default auto-accept jika tidak ada handler spesifik
                }

                if !isAccepted {
                    let rejectPacket = try NearbyFrameCodec.encode(type: .acceptance, payload: AcceptanceFrame(status: .reject))
                    try await sendData(rejectPacket, on: connection)
                    session.fail(with: "Ditolak oleh pengguna lokal.")
                    connection.cancel()
                    return
                }

                // Kirim respon persetujuan
                let acceptPacket = try NearbyFrameCodec.encode(type: .acceptance, payload: AcceptanceFrame(status: .accept))
                try await sendData(acceptPacket, on: connection)

                try session.transition(to: .transferring)

                // 4. Alirkan Berkas Masuk (Decrypt & Write to Disk)
                for item in session.items {
                    let destURL = fileManager.resolveDestinationURL(for: item.fileName)
                    let stagingURL = fileManager.createStagingURL(for: destURL)
                    activeStagingURL = stagingURL

                    FileManager.default.createFile(atPath: stagingURL.path, contents: nil)
                    let fileHandle = try FileHandle(forWritingTo: stagingURL)

                    var itemReceived: Int64 = 0
                    while itemReceived < item.fileSize {
                        let chunkPacket = try await receiveLengthPrefixedData(from: connection)
                        guard chunkPacket.count >= 5 else {
                            throw ReceiverServerError.corruptChunkPacket
                        }

                        // Parse format: ChunkIndex (4B) + IsLast (1B) + EncryptedPayload
                        let isLast = chunkPacket[4] == 1
                        let encryptedPayload = chunkPacket.subdata(in: 5..<chunkPacket.count)

                        // Dekripsi muatan blok
                        let decryptedChunk = try CryptoEngine.decryptAESGCM(
                            ciphertextWithNonceAndTag: encryptedPayload,
                            using: clientKey
                        )

                        try fileHandle.write(contentsOf: decryptedChunk)
                        itemReceived += Int64(decryptedChunk.count)

                        session.updateProgress(
                            transferredBytes: session.transferredBytes + Int64(decryptedChunk.count),
                            speedBytesPerSecond: 0
                        )

                        if isLast { break }
                    }

                    try fileHandle.close()

                    // Finalisasi berkas dari staging ke tujuan akhir (dengan validasi checksum jika ada)
                    try fileManager.finalizeStagingFile(
                        stagingURL: stagingURL,
                        destinationURL: destURL,
                        expectedChecksum: item.sha256Checksum
                    )
                    activeStagingURL = nil
                }

                try session.transition(to: .completed)
                onTransferCompleted?(session)
                connection.cancel()

            } catch {
                if let staging = activeStagingURL {
                    fileManager.cleanupStagingFile(at: staging)
                }
                var failedSession = TransferSession(peerEndpointId: "samsung_client", direction: .incoming, state: .failed)
                failedSession.fail(with: error.localizedDescription)
                onTransferFailed?(failedSession, error)
                connection.cancel()
            }
        }
    }

    // MARK: - Low-Level Network Helpers

    private func sendData(_ data: Data, on connection: NWConnection) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let err = error {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveLengthPrefixedData(from connection: NWConnection) async throws -> Data {
        let lengthHeader = try await receiveExactBytes(count: 4, from: connection)
        let payloadLength = lengthHeader.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        return try await receiveExactBytes(count: Int(payloadLength), from: connection)
    }

    private func receiveExactBytes(count: Int, from connection: NWConnection) async throws -> Data {
        var buffer = Data()
        while buffer.count < count {
            let needed = count - buffer.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { content, _, isComplete, error in
                    if let err = error {
                        continuation.resume(throwing: err)
                    } else if let data = content, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: ReceiverServerError.connectionClosedPrematurely)
                    }
                }
            }
            buffer.append(chunk)
        }
        return buffer
    }
}

public enum ReceiverServerError: Error, Equatable, Sendable {
    case invalidPort(Int)
    case invalidHandshakePayload
    case keyDerivationFailed
    case unexpectedFrame(expected: NearbyFrameType, actual: NearbyFrameType)
    case corruptChunkPacket
    case connectionClosedPrematurely
}
