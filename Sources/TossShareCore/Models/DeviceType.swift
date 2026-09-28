import Foundation

/// Tipe perangkat keras yang didukung oleh protokol Quick Share / Nearby Share.
public enum DeviceType: String, Codable, Sendable, CaseIterable {
    case phone
    case tablet
    case laptop
    case unknown

    public var displayName: String {
        switch self {
        case .phone: return "Phone"
        case .tablet: return "Tablet"
        case .laptop: return "Laptop"
        case .unknown: return "Perangkat"
        }
    }
}
