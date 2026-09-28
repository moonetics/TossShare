import Foundation
import Network

/// Representasi perangkat peer (seperti Samsung Galaxy) yang terdeteksi di jaringan lokal.
public struct PeerDevice: Identifiable, Codable, Sendable, Hashable, Equatable {
    /// Identifier unik untuk SwiftUI Identifiable protokol, menggunakan endpointId mDNS.
    public var id: String { endpointId }

    /// Endpoint ID 4-karakter acak yang dipublikasikan oleh perangkat target via mDNS.
    public var endpointId: String

    /// Nama perangkat yang ramah pengguna (contoh: "Galaxy S24 Ultra", "Galaxy Z Fold 6").
    public var friendlyName: String

    /// Kategori bentuk fisik perangkat.
    public var deviceType: DeviceType

    /// Alamat IPv4 lokal perangkat di subnet Wi-Fi.
    public var ipAddress: String

    /// Port TCP tempat server Quick Share target mendengarkan koneksi masuk.
    public var port: Int

    /// Waktu terakhir kali sinyal mDNS atau beacon BLE perangkat terdeteksi.
    public var lastSeen: Date

    /// Kekuatan sinyal Bluetooth Low Energy dalam dBm (jika terdeteksi dalam jangkauan BLE).
    public var rssi: Int?

    /// Menandakan apakah perangkat berada dalam mode privasi (Hanya Kontak) di mana nama disembunyikan.
    public var isPrivacyMode: Bool

    /// Objek resolusi NWEndpoint native Network.framework (misal: Bonjour service) untuk koneksi TCP langsung.
    public var endpoint: NWEndpoint?

    enum CodingKeys: String, CodingKey {
        case endpointId
        case friendlyName
        case deviceType
        case ipAddress
        case port
        case lastSeen
        case rssi
        case isPrivacyMode
    }

    public init(
        endpointId: String,
        friendlyName: String,
        deviceType: DeviceType,
        ipAddress: String,
        port: Int,
        lastSeen: Date = Date(),
        rssi: Int? = nil,
        isPrivacyMode: Bool = false,
        endpoint: NWEndpoint? = nil
    ) {
        self.endpointId = endpointId
        self.friendlyName = friendlyName
        self.deviceType = deviceType
        self.ipAddress = ipAddress
        self.port = port
        self.lastSeen = lastSeen
        self.rssi = rssi
        self.isPrivacyMode = isPrivacyMode
        self.endpoint = endpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.endpointId = try container.decode(String.self, forKey: .endpointId)
        self.friendlyName = try container.decode(String.self, forKey: .friendlyName)
        self.deviceType = try container.decode(DeviceType.self, forKey: .deviceType)
        self.ipAddress = try container.decode(String.self, forKey: .ipAddress)
        self.port = try container.decode(Int.self, forKey: .port)
        self.lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        self.rssi = try container.decodeIfPresent(Int.self, forKey: .rssi)
        self.isPrivacyMode = try container.decodeIfPresent(Bool.self, forKey: .isPrivacyMode) ?? false
        self.endpoint = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpointId, forKey: .endpointId)
        try container.encode(friendlyName, forKey: .friendlyName)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encode(ipAddress, forKey: .ipAddress)
        try container.encode(port, forKey: .port)
        try container.encode(lastSeen, forKey: .lastSeen)
        try container.encodeIfPresent(rssi, forKey: .rssi)
    }
}

