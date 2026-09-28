//
//  DesignTokens.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI

/// Sistem Token Desain terpusat untuk TossShare (Apple Translucent Glassmorphism).
public enum Theme {
    // MARK: - Color Tokens
    public enum Colors {
        /// Aksen biru AirDrop khas Apple (#007AFF)
        public static let airDropBlue = Color(red: 0.0, green: 0.478, blue: 1.0)

        /// Aksen cyan Quick Share khas Samsung (#00A8FF)
        public static let samsungCyan = Color(red: 0.0, green: 0.658, blue: 1.0)

        /// Gradien identitas merek TossShare: Biru AirDrop ke Cyan Samsung
        public static let gradientBrand = LinearGradient(
            colors: [airDropBlue, samsungCyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Gradien pendaran radar
        public static let gradientRadarWave = LinearGradient(
            colors: [airDropBlue.opacity(0.35), samsungCyan.opacity(0.05)],
            startPoint: .center,
            endPoint: .trailing
        )

        // Warna Semantik Status
        public static let statusScanning = Color(red: 0.0, green: 0.55, blue: 1.0)
        public static let statusTransferring = Color(red: 0.0, green: 0.75, blue: 0.95)
        public static let statusSuccess = Color(red: 0.20, green: 0.78, blue: 0.35)
        public static let statusWarning = Color(red: 1.0, green: 0.60, blue: 0.0)
        public static let statusDanger = Color(red: 1.0, green: 0.27, blue: 0.23)

        // Permukaan & Border Glassmorphic
        public static let borderHairline = Color.primary.opacity(0.12)
        public static let borderGlow = samsungCyan.opacity(0.4)
    }

    // MARK: - Typography Tokens
    public enum Typography {
        public static let largeTitle: Font = .system(size: 26, weight: .bold, design: .rounded)
        public static let title: Font = .system(size: 20, weight: .semibold, design: .rounded)
        public static let headline: Font = .system(size: 15, weight: .semibold, design: .default)
        public static let deviceTitle: Font = .system(size: 13, weight: .medium, design: .default)
        public static let body: Font = .system(size: 12, weight: .regular, design: .default)
        public static let caption: Font = .system(size: 11, weight: .regular, design: .default)
        public static let monospaceSpeed: Font = .system(size: 12, weight: .medium, design: .monospaced)
        public static let monospacePin: Font = .system(size: 20, weight: .bold, design: .monospaced)
    }

    // MARK: - Spacing & Sizing Tokens
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
    }

    public enum Radii {
        public static let small: CGFloat = 6
        public static let button: CGFloat = 8
        public static let card: CGFloat = 14
        public static let avatar: CGFloat = 28
        public static let pill: CGFloat = 999
    }

    // MARK: - Animation Tokens
    public enum Animation {
        /// Durasi pulsing gelombang radar konsentris
        public static let radarPulseDuration: Double = 2.0

        /// Animasi spring lincah untuk interaksi hover dan click
        public static let springSnappy = SwiftUI.Animation.spring(response: 0.32, dampingFraction: 0.72)

        /// Animasi transisi status
        public static let statusTransition = SwiftUI.Animation.easeInOut(duration: 0.25)
    }

    // MARK: - Utility Formatters
    public enum Formatters {
        public static func formatBytes(_ bytes: Int64) -> String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        }

        public static func formatSpeed(_ bytesPerSecond: Double) -> String {
            if bytesPerSecond <= 0 {
                return "0 KB/s"
            }
            let mbPerSec = bytesPerSecond / (1024 * 1024)
            if mbPerSec >= 1.0 {
                return String(format: "%.1f MB/s", mbPerSec)
            } else {
                let kbPerSec = bytesPerSecond / 1024
                return String(format: "%.0f KB/s", kbPerSec)
            }
        }
    }
}
