import Foundation

/// Tipe perangkat keras yang didukung oleh protokol Quick Share / Nearby Share.
public enum DeviceType: String, Codable, Sendable, CaseIterable {
    case phone
    case tablet
    case laptop
    case unknown
}
