import Foundation

/// Arah aliran berkas dalam sesi transfer.
public enum TransferDirection: String, Codable, Sendable, CaseIterable {
    /// Pengiriman berkas dari Mac ke perangkat Samsung (Client mode).
    case outgoing
    /// Penerimaan berkas dari perangkat Samsung ke Mac (Server mode).
    case incoming
}
