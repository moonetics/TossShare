//
//  FileItemCollector.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation

/// Utilitas pengumpul dan perata (flattening) berkas untuk pengiriman multi-file ke Samsung Quick Share.
public struct FileItemCollector: Sendable {

    /// Meratakan daftar URL (bisa berupa berkas reguler maupun direktori/folder)
    /// menjadi daftar berkas fisik satuan, mengabaikan berkas sistem tersembunyi (.DS_Store, dll).
    public static func flattenURLs(_ urls: [URL]) -> [URL] {
        var collectedFiles: [URL] = []
        let fileManager = FileManager.default

        for url in urls {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
                continue
            }

            let fileName = url.lastPathComponent
            if fileName.hasPrefix(".") {
                continue
            }

            if isDir.boolValue {
                // Traversal rekursif seluruh isi folder
                if let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let fileURL as URL in enumerator {
                        let subName = fileURL.lastPathComponent
                        if subName.hasPrefix(".") { continue }

                        if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                           resourceValues.isRegularFile == true {
                            collectedFiles.append(fileURL)
                        }
                    }
                }
            } else {
                collectedFiles.append(url)
            }
        }

        return collectedFiles
    }
}

/// Thread-safe accumulator untuk mengumpulkan URL dari asynchronous drag-and-drop provider.
public final class URLCollector: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()

    public init() {}

    public func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    public func getAll() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}
