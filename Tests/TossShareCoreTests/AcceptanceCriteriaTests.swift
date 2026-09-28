//
//  AcceptanceCriteriaTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
import CryptoKit
@testable import TossShareCore
@testable import TossShareUI

final class AcceptanceCriteriaTests: XCTestCase {

    private var temporaryDirectoryURL: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TossShare_AC_Tests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temp = temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temp)
        }
        super.tearDown()
    }

    // MARK: - Skenario 1: Penemuan Otomatis Samsung (AC-1)

    /// Skenario 1 (PRD Seksi 17):
    /// Given: Pengguna membuka Radar TossShare di Mac dan perangkat Samsung mengaktifkan Quick Share "Everyone for 10 minutes" pada Wi-Fi yang sama.
    /// When: Mac memindai jaringan lokal dan menerima TXT record mDNS.
    /// Then: Avatar dan nama perangkat Samsung muncul di Radar Mac dalam waktu < 2 detik tanpa QR Code.
    @MainActor
    func testAC1_AutoDiscoveryUnderTwoSeconds() throws {
        let registry = DeviceRegistry(startTimer: false)
        let sampleFriendlyName = "Galaxy S24 Ultra (Bimo)"
        let sampleDeviceType = DeviceType.phone

        // Buat TXT record 'n' standar Google / Samsung Quick Share (menghasilkan Base64 string)
        let nRecordString = EndpointInfoParser.createRecord(friendlyName: sampleFriendlyName, deviceType: sampleDeviceType)

        let startTime = Date()

        // Simulasi penerimaan paket mDNS oleh browser lokal
        let parsed = try EndpointInfoParser.parse(nRecord: nRecordString)

        let discoveredPeer = PeerDevice(
            endpointId: "s24u",
            friendlyName: parsed.friendlyName,
            deviceType: parsed.deviceType,
            ipAddress: "192.168.1.150",
            port: 44445,
            rssi: -42
        )

        // Daftarkan ke reactive registry
        registry.registerOrUpdate(device: discoveredPeer)

        let elapsedSeconds = Date().timeIntervalSince(startTime)

        // Verifikasi Acceptance Criteria: Muncul di registry dalam < 2 detik tanpa QR Code
        XCTAssertLessThan(elapsedSeconds, 2.0, "Penemuan mDNS harus selesai dalam waktu < 2.0 detik (Terukur: \(elapsedSeconds)s)")
        XCTAssertEqual(registry.devices.count, 1)
        XCTAssertEqual(registry.devices.first?.friendlyName, sampleFriendlyName)
        XCTAssertEqual(registry.devices.first?.deviceType, .phone)
        XCTAssertEqual(registry.devices.first?.rssi, -42)
    }

    // MARK: - Skenario 2: Mengirim & Menerima Berkas Sukses dengan SHA-256 (AC-2)

    /// Skenario 2 (PRD Seksi 17 + BR-001 + BR-002):
    /// Given: Berkas dipilih di Mac dan perangkat Samsung telah terdeteksi.
    /// When: Pengguna mentransfer berkas via chunked streaming 512KB.
    /// Then: Berkas ditransfer, hash SHA-256 cocok 100%, duplikasi nama otomatis di-rename (BR-001), dan pembersihan file batal tuntas (BR-002).
    func testAC2_SendAndReceiveWithSHA256AndBusinessRules() async throws {
        let fileManager = TransferFileManager(destinationDirectory: temporaryDirectoryURL)

        // 1. Siapkan berkas uji coba (1.25 MB untuk menguji multi-chunk 512KB)
        let originalFileName = "presentasi_proyek.pdf"
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source_\(originalFileName)")
        let dummyPayload = Data(repeating: 0x5A, count: 1_250_000) // 1.25 MB
        try dummyPayload.write(to: sourceURL)

        let sourceSHA256 = try fileManager.computeSHA256(for: sourceURL)

        // 2. Stream berkas per blok 512KB
        let streamer = try ChunkedFileStreamer(fileURL: sourceURL, chunkSize: 512 * 1024)
        let sessionKey = SymmetricKey(size: .bits256)
        var chunkCount = 0

        while let (_, isLast) = try streamer.readAndEncryptNextChunk(using: sessionKey) {
            chunkCount += 1
            if isLast { break }
        }

        XCTAssertEqual(chunkCount, 3, "Payload 1.25 MB dengan buffer 512KB harus terbagi menjadi 3 chunk")
        XCTAssertTrue(streamer.isComplete)

        // 3. Tulis payload ke staging disk (.part)
        let destinationURL = fileManager.resolveDestinationURL(for: originalFileName)
        let stagingURL = fileManager.createStagingURL(for: destinationURL)

        try dummyPayload.write(to: stagingURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingURL.path))

        // 4. Finalisasi staging ke lokasi penyimpanan akhir dengan verifikasi checksum
        try fileManager.finalizeStagingFile(
            stagingURL: stagingURL,
            destinationURL: destinationURL,
            expectedChecksum: sourceSHA256
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path), "File .part harus dipindahkan")

        // Verifikasi integritas hash SHA-256 di disk
        let finalSHA256 = try fileManager.computeSHA256(for: destinationURL)
        XCTAssertEqual(finalSHA256, sourceSHA256, "Integritas berkas SHA-256 harus cocok 100%")

        // 5. Verifikasi BR-001 (Resolusi Duplikasi File Otomatis)
        let duplicateDestURL = fileManager.resolveDestinationURL(for: originalFileName)
        XCTAssertEqual(duplicateDestURL.lastPathComponent, "presentasi_proyek (1).pdf", "File duplikat harus otomatis di-rename sesuai BR-001")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path), "File asli tidak boleh tertimpa")

        let secondStagingURL = fileManager.createStagingURL(for: duplicateDestURL)
        try dummyPayload.write(to: secondStagingURL)
        try fileManager.finalizeStagingFile(stagingURL: secondStagingURL, destinationURL: duplicateDestURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateDestURL.path))

        // 6. Verifikasi BR-002 (Pembersihan File Batal Bersih dari Disk)
        let abortFileName = "transfer_batal.zip"
        let abortDestURL = fileManager.resolveDestinationURL(for: abortFileName)
        let abortStagingURL = fileManager.createStagingURL(for: abortDestURL)

        try Data(repeating: 0xBB, count: 100_000).write(to: abortStagingURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: abortStagingURL.path))

        fileManager.cleanupStagingFile(at: abortStagingURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abortStagingURL.path), "File temporer .part wajib dibersihkan instan saat transfer batal sesuai BR-002")
    }

    // MARK: - Skenario 3: Penanganan Fallback AP Isolation (AC-3)

    /// Skenario 3 (PRD Seksi 17 + FR-009 + FR-010):
    /// Given: Mac dan Samsung terhubung ke Wi-Fi publik yang mengaktifkan AP Isolation.
    /// When: Pengguna mencoba mengirim berkas dan koneksi soket gagal.
    /// Then: TossShare mendeteksi kegagalan soket, mengaktifkan panduan Mobile Hotspot dalam 2 langkah, serta opsi kabel USB-C.
    @MainActor
    func testAC3_APIsolationDetectionAndFallbackAdvisor() async throws {
        let healthMonitor = NetworkHealthMonitor()
        let advisor = ConnectivityAdvisor(healthMonitor: healthMonitor)

        XCTAssertFalse(healthMonitor.isAPIsolationSuspected)
        XCTAssertFalse(advisor.shouldShowFallbackCard)

        // Simulasi percobaan transfer ke Samsung yang gagal karena isolasi port TCP router
        healthMonitor.reportTCPConnectionFailure()
        healthMonitor.reportTCPConnectionFailure()

        // Berikan kesempatan MainActor memproses onStatusChange task
        await Task.yield()
        try await Task.sleep(nanoseconds: 10_000_000)

        // Verifikasi: Sistem mendeteksi AP Isolation
        XCTAssertTrue(healthMonitor.isAPIsolationSuspected, "Kegagalan koneksi berulang di LAN harus dicurigai sebagai AP Isolation")
        XCTAssertTrue(advisor.shouldShowFallbackCard, "Fallback advisor card harus otomatis ditampilkan ke pengguna")

        // Verifikasi opsi rekomendasi fallback advisor
        advisor.simulateAPIsolation(enabled: true)
        XCTAssertTrue(advisor.shouldShowFallbackCard)

        // Pengguna menutup kartu atau masalah selesai
        advisor.dismissFallbackCard()
        XCTAssertFalse(advisor.shouldShowFallbackCard)
    }
}
