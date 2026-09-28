//
//  BatchTransferAndFlatteningTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
@testable import TossShareCore

final class BatchTransferAndFlatteningTests: XCTestCase {

    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tossshare_batch_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    func testResolveBatchDestinationDirectoryFormatAndDedup() throws {
        let fileManager = TransferFileManager(destinationDirectory: tempDirectory)
        let fixedDate = Date(timeIntervalSince1970: 1727530800) // 2024-09-28 13:40 UTC

        let batchDir1 = fileManager.resolveBatchDestinationDirectory(peerName: "Samsung A54", date: fixedDate)
        XCTAssertTrue(batchDir1.lastPathComponent.contains("TossShare - Samsung A54"))
        XCTAssertEqual(batchDir1.deletingLastPathComponent().path, tempDirectory.path)

        // Buat folder fisik batchDir1 untuk memicu collision
        try FileManager.default.createDirectory(at: batchDir1, withIntermediateDirectories: true)

        let batchDir2 = fileManager.resolveBatchDestinationDirectory(peerName: "Samsung A54", date: fixedDate)
        XCTAssertTrue(batchDir2.lastPathComponent.contains("(1)"))
        XCTAssertNotEqual(batchDir1.path, batchDir2.path)

        // Uji sanitasi karakter ilegal pada nama peer
        let batchDirIllegal = fileManager.resolveBatchDestinationDirectory(peerName: "Samsung/Galaxy:Ultra", date: fixedDate)
        XCTAssertFalse(batchDirIllegal.lastPathComponent.contains("/"))
        XCTAssertFalse(batchDirIllegal.lastPathComponent.contains(":"))
    }

    func testFileItemCollectorFlattening() throws {
        // Buat struktur berkas di dalam folder
        let rootFolder = tempDirectory.appendingPathComponent("ProyekDesain")
        let subFolder = rootFolder.appendingPathComponent("Aset")
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)

        let file1 = rootFolder.appendingPathComponent("desain.png")
        let file2 = rootFolder.appendingPathComponent(".DS_Store")
        let file3 = subFolder.appendingPathComponent("ikon.svg")
        let file4 = subFolder.appendingPathComponent(".hidden_config")

        try "image data".write(to: file1, atomically: true, encoding: .utf8)
        try "junk ds_store".write(to: file2, atomically: true, encoding: .utf8)
        try "<svg></svg>".write(to: file3, atomically: true, encoding: .utf8)
        try "secret".write(to: file4, atomically: true, encoding: .utf8)

        // Single external file
        let externalFile = tempDirectory.appendingPathComponent("dokumen.pdf")
        try "pdf data".write(to: externalFile, atomically: true, encoding: .utf8)

        let inputURLs = [rootFolder, externalFile]
        let flattened = FileItemCollector.flattenURLs(inputURLs)

        let fileNames = Set(flattened.map { $0.lastPathComponent })
        XCTAssertEqual(fileNames.count, 3)
        XCTAssertTrue(fileNames.contains("desain.png"))
        XCTAssertTrue(fileNames.contains("ikon.svg"))
        XCTAssertTrue(fileNames.contains("dokumen.pdf"))
        XCTAssertFalse(fileNames.contains(".DS_Store"))
        XCTAssertFalse(fileNames.contains(".hidden_config"))
    }

    func testTransferSessionSavedDirectory() throws {
        let batchDir = tempDirectory.appendingPathComponent("TossShare - Test (2026-09-28)")
        var session = TransferSession(
            peerEndpointId: "test_peer",
            direction: .incoming,
            savedDirectory: batchDir
        )

        XCTAssertEqual(session.savedDirectory, batchDir)

        let item = TransferItem(fileName: "foto.png", mimeType: "image/png", fileSize: 100, localURL: batchDir.appendingPathComponent("foto.png"))
        session.items.append(item)

        XCTAssertEqual(session.items.first?.localURL, batchDir.appendingPathComponent("foto.png"))
    }
}
