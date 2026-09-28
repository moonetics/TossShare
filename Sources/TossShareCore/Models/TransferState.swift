import Foundation

/// Status tahapan siklus hidup sesi transfer berkas.
public enum TransferState: String, Codable, Sendable, CaseIterable {
    /// Sesi diinisiasi tetapi belum memulai koneksi soket.
    case idle

    /// Sedang membuka koneksi soket TCP ke endpoint target.
    case connecting

    /// Sedang melakukan jabat tangan kriptografi UKEY2 dan verifikasi token.
    case authenticating

    /// Menunggu pengguna target mengonfirmasi persetujuan penerimaan berkas (popup PIN).
    case waitingAcceptance

    /// Sedang mengalirkan muatan data biner berkas secara chunked (512KB).
    case transferring

    /// Seluruh berkas berhasil ditransfer dan diverifikasi checksum integritasnya (Terminal).
    case completed

    /// Terjadi kegagalan koneksi, penolakan target, atau kesalahan protokol (Terminal).
    case failed

    /// Sesi dibatalkan oleh inisiatif pengguna lokal atau jarak jauh (Terminal).
    case cancelled

    /// Menandakan apakah status ini merupakan status akhir yang tidak dapat diubah lagi.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .idle, .connecting, .authenticating, .waitingAcceptance, .transferring:
            return false
        }
    }

    /// Memeriksa apakah perpindahan ke `nextState` diperbolehkan sesuai aturan FSM.
    public func canTransition(to nextState: TransferState) -> Bool {
        switch self {
        case .idle:
            return nextState == .connecting || nextState == .cancelled
        case .connecting:
            return nextState == .authenticating || nextState == .failed || nextState == .cancelled
        case .authenticating:
            return nextState == .waitingAcceptance || nextState == .failed || nextState == .cancelled
        case .waitingAcceptance:
            return nextState == .transferring || nextState == .failed || nextState == .cancelled
        case .transferring:
            return nextState == .completed || nextState == .failed || nextState == .cancelled
        case .completed, .failed, .cancelled:
            return false
        }
    }
}
