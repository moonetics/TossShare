import Foundation

/// Entitas utama sesi transfer berkas antara Mac dan perangkat target.
public struct TransferSession: Identifiable, Codable, Sendable, Equatable {
    /// Identifier unik untuk SwiftUI Identifiable protokol.
    public var id: UUID { sessionId }

    /// UUID unik sesi transfer.
    public let sessionId: UUID

    /// Endpoint ID dari perangkat peer lawan komunikasi.
    public let peerEndpointId: String

    /// Arah transfer (outgoing atau incoming).
    public let direction: TransferDirection

    /// Status tahapan transfer saat ini yang diatur oleh Finite State Machine.
    public private(set) var state: TransferState

    /// Token PIN 4-digit untuk verifikasi keamanan visual (contoh: "7492").
    public var authPin: String

    /// Waktu dimulainya aliran data transfer berkas.
    public var startTime: Date?

    /// Waktu berakhirnya sesi (saat completed, failed, atau cancelled).
    public var endTime: Date?

    /// Total ukuran muatan seluruh berkas dalam satuan bytes.
    public var totalBytes: Int64

    /// Jumlah bytes yang telah berhasil dikirimkan atau diterima.
    public var transferredBytes: Int64

    /// Kecepatan transfer saat ini dalam satuan bytes per detik.
    public var speedBytesPerSecond: Double

    /// Daftar manifest berkas yang termasuk dalam sesi ini.
    public var items: [TransferItem]

    /// Direktori penyimpanan batch khusus jika transfer terdiri dari banyak berkas.
    public var savedDirectory: URL?

    /// Pesan deskriptif jika sesi mengalami kegagalan (state == .failed).
    public var errorMessage: String?

    /// Progres transfer dalam rentang 0.0 hingga 1.0.
    public var progress: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(transferredBytes) / Double(totalBytes)))
    }

    /// Menandakan apakah transfer telah selesai secara sempurna.
    public var isCompleted: Bool {
        state == .completed
    }

    public init(
        sessionId: UUID = UUID(),
        peerEndpointId: String,
        direction: TransferDirection,
        state: TransferState = .idle,
        authPin: String = "",
        startTime: Date? = nil,
        endTime: Date? = nil,
        totalBytes: Int64 = 0,
        transferredBytes: Int64 = 0,
        speedBytesPerSecond: Double = 0.0,
        items: [TransferItem] = [],
        savedDirectory: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.sessionId = sessionId
        self.peerEndpointId = peerEndpointId
        self.direction = direction
        self.state = state
        self.authPin = authPin
        self.startTime = startTime
        self.endTime = endTime
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.items = items
        self.savedDirectory = savedDirectory
        self.errorMessage = errorMessage
    }

    /// Mengubah status sesi ke `nextState` dengan validasi ketat FSM.
    /// Melempar `TransferStateError` jika transisi tidak diizinkan atau sesi sudah berstatus terminal.
    public mutating func transition(to nextState: TransferState) throws {
        if state.isTerminal {
            throw TransferStateError.sessionAlreadyTerminal(state)
        }
        guard state.canTransition(to: nextState) else {
            throw TransferStateError.invalidTransition(from: state, to: nextState)
        }
        self.state = nextState

        if nextState == .transferring && startTime == nil {
            startTime = Date()
        }
        if nextState.isTerminal && endTime == nil {
            endTime = Date()
        }
    }

    /// Memperbarui progres streaming berkas secara efisien.
    public mutating func updateProgress(transferredBytes: Int64, speedBytesPerSecond: Double) {
        self.transferredBytes = transferredBytes
        self.speedBytesPerSecond = speedBytesPerSecond
    }

    /// Menandai sesi gagal dengan pesan kesalahan spesifik.
    public mutating func fail(with message: String) {
        do {
            try transition(to: .failed)
            self.errorMessage = message
        } catch {
            self.errorMessage = message
        }
    }
}
