import Foundation

/// Error yang dilempar ketika terjadi pelanggaran transisi Finite State Machine pada TransferSession.
public enum TransferStateError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidTransition(from: TransferState, to: TransferState)
    case sessionAlreadyTerminal(TransferState)

    public var description: String {
        switch self {
        case .invalidTransition(let from, let to):
            return "Transisi state tidak valid: tidak dapat berpindah dari '\(from.rawValue)' ke '\(to.rawValue)'."
        case .sessionAlreadyTerminal(let state):
            return "Sesi transfer telah berada dalam status terminal '\(state.rawValue)' dan tidak dapat diubah lagi."
        }
    }
}
