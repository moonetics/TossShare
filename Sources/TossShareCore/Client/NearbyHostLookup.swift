//
//  NearbyHostLookup.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Darwin
import Foundation

/// Utilitas pencarian nama host (Reverse DNS PTR) untuk mendeteksi nama perangkat riil dari alamat IPv4.
public enum NearbyHostLookup: Sendable {

    /// Melakukan pencarian Reverse DNS (PTR) secara sinkron menggunakan getnameinfo POSIX.
    /// Wajib dipanggil pada thread latar belakang (background queue).
    public static func hostname(forIPv4 ip: String) -> String? {
        let trimmedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIP.isEmpty && trimmedIP != "mDNS" else { return nil }

        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, trimmedIP, &addr.sin_addr) == 1 else {
            return nil
        }

        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                getnameinfo(
                    saPtr,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }

        guard result == 0 else { return nil }
        var rawHost = String(cString: hostBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawHost.isEmpty else { return nil }

        // Bersihkan akhiran domain lokal seperti ".local" atau ".lan" jika ada
        if rawHost.hasSuffix(".local") {
            rawHost = String(rawHost.dropLast(6))
        } else if rawHost.hasSuffix(".local.") {
            rawHost = String(rawHost.dropLast(7))
        } else if rawHost.hasSuffix(".lan") {
            rawHost = String(rawHost.dropLast(4))
        }

        // Ganti underscore atau tanda pemisah jika perlu
        return rawHost.isEmpty ? nil : rawHost
    }

    /// API Asynchronous Swift Concurrency yang aman dijalankan dari actor mana pun tanpa memblokir thread.
    public static func lookupHostname(forIPv4 ip: String) async -> String? {
        await Task.detached(priority: .utility) {
            Self.hostname(forIPv4: ip)
        }.value
    }
}
