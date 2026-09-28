//
//  TossShareCore.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation

/// Namespace utama untuk logika inti protokol TossShare (Quick Share kompatibel).
public enum TossShareCore {
    /// Versi library inti TossShare.
    public static let version = "1.0.0"

    /// Tipe layanan mDNS standar untuk protokol Google/Samsung Quick Share.
    public static let mdnsServiceType = "_FC9F5ED42C8A._tcp."
    public static let quickShareMDNSServiceType = mdnsServiceType

    /// UUID Layanan BLE Fast Pair / Quick Share.
    public static let quickShareServiceUUID = "FE2C"
    public static let bleServiceUUIDStrings = [
        "FE2C",
        "FC12",
        "FEF3"
    ]
}
