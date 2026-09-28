import Foundation

/// Penyedia data mock realistis untuk keperluan pengujian unit dan preview antarmuka TossShare.
public struct MockDeviceSeeder: Sendable {
    /// Daftar perangkat Samsung tipikal di jaringan lokal dalam kondisi siaga (idle).
    public static let defaultPeers: [PeerDevice] = [
        PeerDevice(
            endpointId: "s24u",
            friendlyName: "Galaxy S24 Ultra",
            deviceType: .phone,
            ipAddress: "192.168.1.105",
            port: 44445,
            lastSeen: Date(),
            rssi: -45
        ),
        PeerDevice(
            endpointId: "fld6",
            friendlyName: "Galaxy Z Fold 6",
            deviceType: .phone,
            ipAddress: "192.168.1.112",
            port: 44445,
            lastSeen: Date(),
            rssi: -58
        ),
        PeerDevice(
            endpointId: "tbs9",
            friendlyName: "Galaxy Tab S9",
            deviceType: .tablet,
            ipAddress: "192.168.1.120",
            port: 44445,
            lastSeen: Date(),
            rssi: -52
        )
    ]

    /// Perangkat dengan kekuatan sinyal BLE marjinal / lemah (-88 dBm).
    public static let weakSignalPeer = PeerDevice(
        endpointId: "wk01",
        friendlyName: "Galaxy A55 (Tepi Jangkauan)",
        deviceType: .phone,
        ipAddress: "192.168.1.199",
        port: 44445,
        lastSeen: Date(),
        rssi: -88
    )

    /// Perangkat pada segmen subnet yang berbeda (menyimulasikan AP Isolation).
    public static let apIsolatedPeer = PeerDevice(
        endpointId: "iso1",
        friendlyName: "Galaxy S23 (Subnet Terisolasi)",
        deviceType: .phone,
        ipAddress: "10.0.0.45",
        port: 44445,
        lastSeen: Date(),
        rssi: -50
    )

    /// Membuat instance sesi transfer aktif (outgoing) dengan progres ~65% dan kecepatan 28.5 MB/s.
    public static func makeTransferringSession() -> TransferSession {
        let total: Int64 = 150_000_000 // 150 MB
        let transferred: Int64 = 97_500_000 // 97.5 MB (~65%)
        let items = [
            TransferItem(
                itemId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                fileName: "Liburan_Bali_4K.mov",
                mimeType: "video/quicktime",
                fileSize: 150_000_000,
                sha256Checksum: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            )
        ]

        return TransferSession(
            sessionId: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            peerEndpointId: "s24u",
            direction: .outgoing,
            state: .transferring,
            authPin: "4821",
            startTime: Date().addingTimeInterval(-15),
            endTime: nil,
            totalBytes: total,
            transferredBytes: transferred,
            speedBytesPerSecond: 28_500_000, // 28.5 MB/s
            items: items
        )
    }

    /// Membuat instance sesi transfer yang telah selesai sempurna (incoming) dengan dokumen PDF.
    public static func makeCompletedSession() -> TransferSession {
        let total: Int64 = 4_500_000
        return TransferSession(
            sessionId: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
            peerEndpointId: "fld6",
            direction: .incoming,
            state: .completed,
            authPin: "9012",
            startTime: Date().addingTimeInterval(-30),
            endTime: Date(),
            totalBytes: total,
            transferredBytes: total,
            speedBytesPerSecond: 0,
            items: [
                TransferItem(
                    itemId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    fileName: "Dokumen_Kontrak.pdf",
                    mimeType: "application/pdf",
                    fileSize: total,
                    sha256Checksum: "abcd1234ef5678"
                )
            ]
        )
    }
}
