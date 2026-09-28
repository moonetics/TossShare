import Foundation

/// Representasi metadata berkas individual yang ditransfer dalam satu sesi.
public struct TransferItem: Identifiable, Codable, Sendable, Equatable, Hashable {
    /// Identifier unik untuk SwiftUI Identifiable protokol.
    public var id: UUID { itemId }

    /// UUID unik berkas dalam manifest transfer.
    public let itemId: UUID

    /// Nama berkas lengkap beserta ekstensinya (contoh: "foto_liburan.jpg", "laporan.pdf").
    public var fileName: String

    /// Tipe MIME berkas (contoh: "image/jpeg", "application/pdf").
    public var mimeType: String

    /// Ukuran total berkas dalam satuan bytes.
    public var fileSize: Int64

    /// Lokasi berkas di sistem penyimpanan lokal Mac (opsional untuk berkas masuk sebelum ditulis).
    public var localURL: URL?

    /// Hash ringkasan SHA-256 berkas untuk memvalidasi integritas data setelah transfer.
    public var sha256Checksum: String?

    public init(
        itemId: UUID = UUID(),
        fileName: String,
        mimeType: String,
        fileSize: Int64,
        localURL: URL? = nil,
        sha256Checksum: String? = nil
    ) {
        self.itemId = itemId
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.localURL = localURL
        self.sha256Checksum = sha256Checksum
    }
}
