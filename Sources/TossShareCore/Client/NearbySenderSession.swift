//
//  NearbySenderSession.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import Network
import CryptoKit

final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func testAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if flag { return false }
        flag = true
        return true
    }
}

/// Mengelola sesi pengiriman berkas dari Mac ke perangkat Samsung target (Client mode).
public final class NearbySenderSession: @unchecked Sendable {

    public private(set) var session: TransferSession
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.tossshare.sender.session", qos: .userInitiated)

    public var onProgressUpdate: (@Sendable (TransferSession) -> Void)?
    public var onStateChange: (@Sendable (TransferSession) -> Void)?

    public init(peerEndpointId: String, items: [TransferItem]) {
        let totalSize = items.reduce(0) { $0 + $1.fileSize }
        self.session = TransferSession(
            peerEndpointId: peerEndpointId,
            direction: .outgoing,
            state: .idle,
            totalBytes: totalSize,
            items: items
        )
    }

    deinit {
        cancel()
    }

    // MARK: - Transfer Orchestration

    /// Menjalankan alur pengiriman lengkap: TCP Connect -> UKEY2 Handshake -> Metadata -> Streaming -> Selesai.
    public func start(host: String, port: Int) async throws {
        // 1. Inisiasi Koneksi TCP
        try session.transition(to: .connecting)
        notifyStateChange()

        let endpointHost = NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw SenderSessionError.invalidPort(port)
        }

        let nwConn = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        self.connection = nwConn

        let flag = AtomicFlag()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nwConn.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    if flag.testAndSet() {
                        continuation.resume()
                    }
                case .failed(let err):
                    if flag.testAndSet() {
                        continuation.resume(throwing: err)
                    }
                case .cancelled:
                    if flag.testAndSet() {
                        continuation.resume(throwing: SenderSessionError.connectionCancelled)
                    }
                default:
                    break
                }
            }
            nwConn.start(queue: self.queue)
        }

        // 2. Jabat Tangan UKEY2
        try session.transition(to: .authenticating)
        notifyStateChange()

        let handshake = UKEY2Handshake(role: .client)
        let clientInitPayload = handshake.makeClientInitPayload()
        let wirePacket = WireEncoding.encodeLengthPrefixed(clientInitPayload)

        try await sendData(wirePacket)

        // Terima ServerInit
        let serverInitPacket = try await receiveLengthPrefixedData()
        guard serverInitPacket.count >= 2 else {
            throw SenderSessionError.invalidHandshakePayload
        }

        let pubKeyLength = Int(serverInitPacket[0])
        let pubKeyEnd = 1 + pubKeyLength
        guard serverInitPacket.count >= pubKeyEnd + 1 else {
            throw SenderSessionError.invalidHandshakePayload
        }

        let serverPubKey = serverInitPacket.subdata(in: 1..<pubKeyEnd)
        let saltLength = Int(serverInitPacket[pubKeyEnd])
        let saltEnd = pubKeyEnd + 1 + saltLength
        guard serverInitPacket.count >= saltEnd else {
            throw SenderSessionError.invalidHandshakePayload
        }
        let serverSalt = serverInitPacket.subdata(in: (pubKeyEnd + 1)..<saltEnd)

        try handshake.processServerInit(serverPublicKeyData: serverPubKey, serverSalt: serverSalt)

        guard let pin = handshake.authPin, let clientKey = handshake.clientKey else {
            throw SenderSessionError.cryptoKeyDerivationFailed
        }
        session.authPin = pin

        // 3. Kirim Metadata Pengenalan (IntroductionFrame)
        try session.transition(to: .waitingAcceptance)
        notifyStateChange()

        let introFrame = IntroductionFrame(pin: pin, items: session.items)
        let introPacket = try NearbyFrameCodec.encode(type: .introduction, payload: introFrame)
        try await sendData(introPacket)

        // 4. Tunggu Respon Penerimaan (AcceptanceFrame)
        let responsePacket = try await receiveLengthPrefixedData()
        let (frameType, payload) = try NearbyFrameCodec.decodeTypeAndPayload(from: responsePacket)
        guard frameType == .acceptance else {
            throw SenderSessionError.unexpectedFrame(expected: .acceptance, actual: frameType)
        }

        let acceptance = try NearbyFrameCodec.decodePayload(AcceptanceFrame.self, from: payload)
        guard acceptance.status == .accept else {
            session.fail(with: "Permintaan transfer ditolak oleh target.")
            notifyStateChange()
            throw SenderSessionError.transferRejected
        }

        // 5. Alirkan Berkas Masuk (Chunked Streaming 512KB)
        try session.transition(to: .transferring)
        notifyStateChange()

        for item in session.items {
            guard let localURL = item.localURL else { continue }
            let streamer = try ChunkedFileStreamer(fileURL: localURL)

            while let (chunkPacket, _) = try streamer.readAndEncryptNextChunk(using: clientKey) {
                try await sendData(chunkPacket)
                session.updateProgress(
                    transferredBytes: session.transferredBytes + Int64(streamer.chunkSize),
                    speedBytesPerSecond: streamer.currentSpeedBytesPerSecond
                )
                onProgressUpdate?(session)
            }
            streamer.close()
        }

        // 6. Transfer Selesai Sempurna
        try session.transition(to: .completed)
        notifyStateChange()
    }

    /// Membatalkan sesi transfer secara aktif.
    public func cancel() {
        if !session.state.isTerminal {
            try? session.transition(to: .cancelled)
            notifyStateChange()
        }
        connection?.cancel()
        connection = nil
    }

    // MARK: - Low-Level Network Helpers

    private func sendData(_ data: Data) async throws {
        guard let conn = connection else { throw SenderSessionError.connectionNotOpen }
        return try await withCheckedThrowingContinuation { continuation in
            conn.send(content: data, completion: .contentProcessed { error in
                if let err = error {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveLengthPrefixedData() async throws -> Data {
        guard let conn = connection else { throw SenderSessionError.connectionNotOpen }

        // 1. Baca 4-byte header panjang
        let lengthHeader = try await receiveExactBytes(count: 4, on: conn)
        let payloadLength = lengthHeader.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        // 2. Baca muatan payload lengkap
        let payload = try await receiveExactBytes(count: Int(payloadLength), on: conn)
        return payload
    }

    private func receiveExactBytes(count: Int, on conn: NWConnection) async throws -> Data {
        var buffer = Data()
        while buffer.count < count {
            let needed = count - buffer.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                conn.receive(minimumIncompleteLength: 1, maximumLength: needed) { content, _, isComplete, error in
                    if let err = error {
                        continuation.resume(throwing: err)
                    } else if let data = content, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: SenderSessionError.connectionClosedPrematurely)
                    }
                }
            }
            buffer.append(chunk)
        }
        return buffer
    }

    private func notifyStateChange() {
        onStateChange?(session)
    }
}

public enum SenderSessionError: Error, Equatable, Sendable {
    case invalidPort(Int)
    case connectionNotOpen
    case connectionCancelled
    case connectionClosedPrematurely
    case invalidHandshakePayload
    case cryptoKeyDerivationFailed
    case unexpectedFrame(expected: NearbyFrameType, actual: NearbyFrameType)
    case transferRejected
}
