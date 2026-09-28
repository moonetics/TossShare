//
//  TransferFileManager.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import CryptoKit

/// Mengelola penyimpanan berkas di disk, penanganan duplikasi (BR-001), dan pembersihan staging (BR-002).
public struct TransferFileManager: Sendable {

    /// Direktori penyimpanan berkas masuk (default: ~/Downloads).
    public let destinationDirectory: URL

    public init(destinationDirectory: URL? = nil) {
        if let dir = destinationDirectory {
            self.destinationDirectory = dir
        } else {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            self.destinationDirectory = downloads ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        }
    }

    // MARK: - Business Rule BR-001: Auto-Rename Duplikasi

    /// Menentukan URL tujuan akhir berkas. Jika berkas sudah ada, menambahkan nomor urut otomatis (contoh: "foto (1).jpg").
    public func resolveDestinationURL(for fileName: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? destinationDirectory
        let fileManager = FileManager.default

        let sanitizedName = (fileName as NSString).lastPathComponent
        var targetURL = dir.appendingPathComponent(sanitizedName)

        guard fileManager.fileExists(atPath: targetURL.path) else {
            return targetURL
        }

        let nameWithoutExtension = (sanitizedName as NSString).deletingPathExtension
        let fileExtension = (sanitizedName as NSString).pathExtension

        var counter = 1
        while true {
            let newName: String
            if fileExtension.isEmpty {
                newName = "\(nameWithoutExtension) (\(counter))"
            } else {
                newName = "\(nameWithoutExtension) (\(counter)).\(fileExtension)"
            }

            targetURL = dir.appendingPathComponent(newName)
            if !fileManager.fileExists(atPath: targetURL.path) {
                return targetURL
            }
            counter += 1
        }
    }

    // MARK: - Business Rule BR-002: Staging & Pembersihan File Batal

    /// Menghasilkan URL berkas tersembunyi temporer (.filename.part) untuk proses penulisan sementara.
    public func createStagingURL(for destinationURL: URL) -> URL {
        let parentDir = destinationURL.deletingLastPathComponent()
        let stagingName = ".\(destinationURL.lastPathComponent).part"
        return parentDir.appendingPathComponent(stagingName)
    }

    /// Menghapus berkas staging jika transfer dibatalkan atau soket terputus.
    public func cleanupStagingFile(at stagingURL: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: stagingURL.path) {
            try? fileManager.removeItem(at: stagingURL)
        }
    }

    /// Memverifikasi hash SHA-256 (jika disediakan) dan memindahkan berkas secara atomik dari staging ke tujuan akhir.
    public func finalizeStagingFile(
        stagingURL: URL,
        destinationURL: URL,
        expectedChecksum: String? = nil
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: stagingURL.path) else {
            throw TransferFileError.stagingFileNotFound(stagingURL)
        }

        // 1. Verifikasi Checksum SHA-256 secara streaming jika ada
        if let expected = expectedChecksum, !expected.isEmpty {
            let actualHash = try computeSHA256(for: stagingURL)
            if actualHash.lowercased() != expected.lowercased() {
                // Hapus berkas korup segera
                cleanupStagingFile(at: stagingURL)
                throw TransferFileError.checksumMismatch(expected: expected, actual: actualHash)
            }
        }

        // 2. Pastikan direktori tujuan tersedia
        let targetDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: targetDir.path) {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        // 3. Pindahkan file secara atomik
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
    }

    // MARK: - Streaming Checksum Computation (RAM < 60 MB)

    /// Menghitung SHA-256 berkas di disk secara chunked tanpa membaca seluruh isi berkas ke memori.
    public func computeSHA256(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 512 * 1024 // 512 KB

        while let chunk = try handle.read(upToCount: bufferSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum TransferFileError: Error, Equatable, Sendable {
    case stagingFileNotFound(URL)
    case checksumMismatch(expected: String, actual: String)
    case diskWriteFailed(String)
}
