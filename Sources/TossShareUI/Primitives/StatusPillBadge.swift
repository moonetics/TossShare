//
//  StatusPillBadge.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI

public enum StatusBadgeType: Sendable {
    case ready
    case scanning
    case transferring
    case success
    case warning(String)
    case danger(String)

    public var tintColor: Color {
        switch self {
        case .ready:
            return Theme.Colors.statusSuccess
        case .scanning:
            return Theme.Colors.statusScanning
        case .transferring:
            return Theme.Colors.statusTransferring
        case .success:
            return Theme.Colors.statusSuccess
        case .warning:
            return Theme.Colors.statusWarning
        case .danger:
            return Theme.Colors.statusDanger
        }
    }

    public var title: String {
        switch self {
        case .ready:
            return "Siap Menerima"
        case .scanning:
            return "Memindai Jaringan..."
        case .transferring:
            return "Mentransfer..."
        case .success:
            return "Transfer Selesai"
        case .warning(let msg):
            return msg
        case .danger(let msg):
            return msg
        }
    }

    public var shouldPulse: Bool {
        switch self {
        case .scanning, .transferring:
            return true
        default:
            return false
        }
    }
}

/// Badge status kapsul glassmorphic dengan indikator titik berdenyut.
public struct StatusPillBadge: View {
    public let type: StatusBadgeType
    private let customTitle: String?
    private let customColor: Color?
    private let customPulse: Bool?

    @State private var isDotPulsing: Bool = false

    public init(type: StatusBadgeType) {
        self.type = type
        self.customTitle = nil
        self.customColor = nil
        self.customPulse = nil
    }

    public init(text: String, style: StatusBadgeType = .ready, isPulsing: Bool? = nil) {
        self.type = style
        self.customTitle = text
        self.customColor = style.tintColor
        self.customPulse = isPulsing
    }

    public var body: some View {
        let displayTitle = customTitle ?? type.title
        let displayColor = customColor ?? type.tintColor
        let isPulsingEnabled = customPulse ?? type.shouldPulse

        HStack(spacing: 6) {
            // Indikator Dot
            Circle()
                .fill(displayColor)
                .frame(width: 7, height: 7)
                .scaleEffect(isPulsingEnabled && isDotPulsing ? 1.35 : 1.0)
                .opacity(isPulsingEnabled && isDotPulsing ? 0.6 : 1.0)
                .animation(
                    isPulsingEnabled
                        ? Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .default,
                    value: isDotPulsing
                )

            // Label Status
            Text(displayTitle)
                .font(Theme.Typography.caption)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(displayColor.opacity(0.35), lineWidth: 1)
                )
        )
        .onAppear {
            if isPulsingEnabled {
                isDotPulsing = true
            }
        }
    }
}
