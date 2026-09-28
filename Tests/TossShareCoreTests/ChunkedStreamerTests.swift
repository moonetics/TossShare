//
//  ChunkedStreamerTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
import CryptoKit
@testable import TossShareCore

final class ChunkedStreamerTests: XCTestCase {

    var tempDirectory: URL!

    override func setUpWithError() throws {
        let tempBase = FileManager.default.temporaryDirectory
        tempDirectory = tempBase.appendingPathComponent("tossshare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - TransferFileManager Tests (BR-001 & BR-002)

    func testAutoRenameDuplicateFile() throws {
        let fileManager = TransferFileManager(destinationDirectory: tempDirectory)

        // 1. Belum ada file kembar
        let url1 = fileManager.resolveDestinationURL(for: "laporan.pdf")
        XCTAssertEqual(url1.lastPathComponent, "laporan.pdf")

        // Buat laporan.pdf di disk
        FileManager.default.createFile(atPath: url1.path, contents: "data awal".data(using: .utf8)!)

        // 2. Sekarang laporan.pdf ada -> harus jadi laporan (1).pdf
        let url2 = fileManager.resolveDestinationURL(for: "laporan.pdf")
        XCTAssertEqual(url2.lastPathComponent, "laporan (1).pdf")

        // Buat laporan (1).pdf di disk
        FileManager.default.createFile(atPath: url2.path, contents: "data kedua".data(using: .utf8)!)

        // 3. Sekarang laporan.pdf dan laporan (1).pdf ada -> harus jadi laporan (2).pdf
        let url3 = fileManager.resolveDestinationURL(for: "laporan.pdf")
        XCTAssertEqual(url3.lastPathComponent, "laporan (2).pdf")
    }

    func testStagingFileFinalizationAndChecksum() throws {
        let fileManager = TransferFileManager(destinationDirectory: tempDirectory)
        let destURL = tempDirectory.appendingPathComponent("hasil_transfer.dat")
        let stagingURL = fileManager.createStagingURL(for: destURL)

        XCTAssertTrue(stagingURL.lastPathComponent.hasPrefix("."))
        XCTAssertTrue(stagingURL.lastPathComponent.hasSuffix(".part"))

        // Tulis data ke staging
        let testData = "Muatan berkas rahasia TossShare".data(using: .utf8)!
        try testData.write(to: stagingURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingURL.path))

        let expectedHash = CryptoEngine.sha256Hex(for: testData)

        // Finalisasi berkas
        try fileManager.finalizeStagingFile(
            stagingURL: stagingURL,
            destinationURL: destURL,
            expectedChecksum: expectedHash
        )

        // Verifikasi hasil
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path), "Staging file harus sudah dipindahkan.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path), "Destination file harus tersedia di disk.")
        let readData = try Data(contentsOf: destURL)
        XCTAssertEqual(readData, testData)
    }

    func testStagingChecksumMismatchDeletesPartFile() throws {
        let fileManager = TransferFileManager(destinationDirectory: tempDirectory)
        let destURL = tempDirectory.appendingPathComponent("file_korup.dat")
        let stagingURL = fileManager.createStagingURL(for: destURL)

        let testData = "Data asli".data(using: .utf8)!
        try testData.write(to: stagingURL)

        // Coba finalisasi dengan hash yang salah
        let wrongHash = "0000000000000000000000000000000000000000000000000000000000000000"
        XCTAssertThrowsError(try fileManager.finalizeStagingFile(
            stagingURL: stagingURL,
            destinationURL: destURL,
            expectedChecksum: wrongHash
        )) { error in
            guard case TransferFileError.checksumMismatch = error else {
                XCTFail("Harus melempar checksumMismatch.")
                return
            }
        }

        // BR-002: File korup harus otomatis dibersihkan dari disk
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path), "File .part harus dihapus saat checksum mismatch.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destURL.path), "File final tidak boleh tercipta jika checksum korup.")
    }

    func testCancelledTransferCleanup() throws {
        let fileManager = TransferFileManager(destinationDirectory: tempDirectory)
        let destURL = tempDirectory.appendingPathComponent("batal.dat")
        let stagingURL = fileManager.createStagingURL(for: destURL)

        try "data parsial".data(using: .utf8)!.write(to: stagingURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingURL.path))

        // Simulasi cancel
        fileManager.cleanupStagingFile(at: stagingURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path), "Pembersihan staging harus tuntas.")
    }

    // MARK: - Chunked Streaming Tests (512KB Buffer)

    func testChunkedStreamerBufferConstraint() throws {
        // Buat file uji 1.5 MB (Tepat 3 chunk 512KB)
        let totalSize: Int = 3 * ChunkedFileStreamer.defaultChunkSize
        let randomBytes = CryptoEngine.secureRandomBytes(count: totalSize)
        let sourceURL = tempDirectory.appendingPathComponent("source_1_5mb.bin")
        try randomBytes.write(to: sourceURL)

        let streamer = try ChunkedFileStreamer(fileURL: sourceURL)
        let key = SymmetricKey(size: .bits256)

        var chunksRead = 0
        var reassembledData = Data()
        while let chunk = try streamer.readAndEncryptNextChunk(using: key) {
            var packet = chunk.packet
            let isLast = chunk.isLast
            chunksRead += 1
            if chunksRead < 3 {
                XCTAssertFalse(isLast)
            } else {
                XCTAssertTrue(isLast)
            }

            // Dekode packet length-prefixed
            let payload = try XCTUnwrap(WireEncoding.decodeLengthPrefixed(from: &packet))
            XCTAssertGreaterThanOrEqual(payload.count, 5)

            // Dekripsi chunk
            let encrypted = payload.subdata(in: 5..<payload.count)
            let decrypted = try CryptoEngine.decryptAESGCM(ciphertextWithNonceAndTag: encrypted, using: key)
            reassembledData.append(decrypted)
        }

        XCTAssertEqual(chunksRead, 3, "File 1.5 MB harus diproses tepat dalam 3 chunk 512KB.")
        XCTAssertEqual(reassembledData, randomBytes, "Data hasil streaming terenkripsi harus identik bit-per-bit.")
        XCTAssertTrue(streamer.isComplete)
    }

    // MARK: - Loopback Integration Test (Sender -> Receiver)

    func testLoopbackTransferSimulation() async throws {
        let loopbackPort: UInt16 = 54321
        let receiverDir = tempDirectory.appendingPathComponent("receiver_download")
        try FileManager.default.createDirectory(at: receiverDir, withIntermediateDirectories: true)

        let receiverFileManager = TransferFileManager(destinationDirectory: receiverDir)
        let receiverServer = NearbyReceiverServer(
            port: loopbackPort,
            friendlyName: "Mac Loopback Test",
            fileManager: receiverFileManager
        )

        // 1. Siapkan file kiriman (750 KB)
        let testFileSize = 750 * 1024
        let filePayload = CryptoEngine.secureRandomBytes(count: testFileSize)
        let fileChecksum = CryptoEngine.sha256Hex(for: filePayload)
        let sourceURL = tempDirectory.appendingPathComponent("laporan_keuangan.pdf")
        try filePayload.write(to: sourceURL)

        let item = TransferItem(
            fileName: "laporan_keuangan.pdf",
            mimeType: "application/pdf",
            fileSize: Int64(testFileSize),
            localURL: sourceURL,
            sha256Checksum: fileChecksum
        )

        // 2. Start Receiver Server
        let transferCompletedExpectation = expectation(description: "Receiver completes transfer")
        receiverServer.onTransferCompleted = { session in
            transferCompletedExpectation.fulfill()
        }
        receiverServer.onRequestAcceptance = { session in
            return true // Auto accept
        }

        try receiverServer.start()

        // 3. Beri sedikit waktu untuk soket listener terbuka
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // 4. Start Sender Session
        let sender = NearbySenderSession(peerEndpointId: "test_peer", items: [item])
        try await sender.start(host: "127.0.0.1", port: Int(loopbackPort))

        // 5. Tunggu proses transfer tuntas
        await fulfillment(of: [transferCompletedExpectation], timeout: 5.0)

        // 6. Verifikasi berkas di folder penerima
        let receivedFileURL = receiverDir.appendingPathComponent("laporan_keuangan.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: receivedFileURL.path))

        let receivedData = try Data(contentsOf: receivedFileURL)
        XCTAssertEqual(receivedData, filePayload, "Berkas yang diterima harus identik 100% dengan berkas yang dikirim.")
        XCTAssertEqual(CryptoEngine.sha256Hex(for: receivedData), fileChecksum)

        receiverServer.stop()
    }
}
