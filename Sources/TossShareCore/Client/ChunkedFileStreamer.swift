//
//  ChunkedFileStreamer.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import CryptoKit

/// Mengalirkan berkas secara chunked dengan buffer 512KB dan enkripsi per-blok untuk menjaga RAM < 60 MB.
public final class ChunkedFileStreamer: @unchecked Sendable {

    /// Ukuran buffer standar (512 KB) sesuai batasan arsitektur NFR-005.
    public static let defaultChunkSize: Int = 512 * 1024

    public let fileURL: URL
    public let fileSize: Int64
    public let chunkSize: Int

    private var fileHandle: FileHandle?
    public private(set) var transferredBytes: Int64 = 0
    public private(set) var chunkIndex: UInt32 = 0
    private var startTime: Date?
    private var lastSpeedCheckTime: Date?
    private var lastSpeedCheckBytes: Int64 = 0
    public private(set) var currentSpeedBytesPerSecond: Double = 0.0

    public var isComplete: Bool {
        transferredBytes >= fileSize
    }

    public init(fileURL: URL, chunkSize: Int = ChunkedFileStreamer.defaultChunkSize) throws {
        self.fileURL = fileURL
        self.chunkSize = chunkSize

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        self.fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        self.fileHandle = try FileHandle(forReadingFrom: fileURL)
    }

    deinit {
        close()
    }

    public func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: - Streaming Generator

    /// Membaca blok 512KB berikutnya, mengenkripsinya dengan kunci sesi, dan membungkusnya dalam paket terbingkai.
    public func readAndEncryptNextChunk(using key: SymmetricKey) throws -> (packet: Data, isLast: Bool)? {
        guard let handle = fileHandle else { return nil }

        if startTime == nil {
            startTime = Date()
            lastSpeedCheckTime = startTime
        }

        guard let rawChunk = try handle.read(upToCount: chunkSize), !rawChunk.isEmpty else {
            return nil
        }

        transferredBytes += Int64(rawChunk.count)
        let isLast = (transferredBytes >= fileSize)

        // 1. Enkripsi blok data biner dengan AES-GCM
        let encryptedPayload = try CryptoEngine.encryptAESGCM(plaintext: rawChunk, using: key)

        // 2. Format paket biner: ChunkIndex (4B) + IsLast (1B) + EncryptedPayload
        var packetBody = Data()
        var indexBigEndian = chunkIndex.bigEndian
        packetBody.append(Data(bytes: &indexBigEndian, count: 4))
        packetBody.append(isLast ? 1 : 0)
        packetBody.append(encryptedPayload)

        chunkIndex += 1
        updateSpeedCalculation()

        let lengthPrefixedPacket = WireEncoding.encodeLengthPrefixed(packetBody)
        return (lengthPrefixedPacket, isLast)
    }

    // MARK: - Speed Meter

    private func updateSpeedCalculation() {
        let now = Date()
        guard let lastTime = lastSpeedCheckTime else {
            lastSpeedCheckTime = now
            return
        }

        let elapsed = now.timeIntervalSince(lastTime)
        if elapsed >= 0.5 { // Update speedometer tiap 500ms
            let bytesDelta = transferredBytes - lastSpeedCheckBytes
            currentSpeedBytesPerSecond = Double(bytesDelta) / elapsed
            lastSpeedCheckTime = now
            lastSpeedCheckBytes = transferredBytes
        }
    }
}
