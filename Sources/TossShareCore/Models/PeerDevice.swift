import Foundation

/// Representasi perangkat peer (seperti Samsung Galaxy) yang terdeteksi di jaringan lokal.
public struct PeerDevice: Identifiable, Codable, Sendable, Hashable, Equatable {
    /// Identifier unik untuk SwiftUI Identifiable protokol, menggunakan endpointId mDNS.
    public var id: String { endpointId }

    /// Endpoint ID 4-karakter acak yang dipublikasikan oleh perangkat target via mDNS.
    public let endpointId: String

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

    public init(
        endpointId: String,
        friendlyName: String,
        deviceType: DeviceType,
        ipAddress: String,
        port: Int,
        lastSeen: Date = Date(),
        rssi: Int? = nil
    ) {
        self.endpointId = endpointId
        self.friendlyName = friendlyName
        self.deviceType = deviceType
        self.ipAddress = ipAddress
        self.port = port
        self.lastSeen = lastSeen
        self.rssi = rssi
    }
}
