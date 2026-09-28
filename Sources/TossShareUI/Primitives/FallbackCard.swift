//
//  FallbackCard.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI

public enum FallbackReason: Sendable {
    case apIsolationDetected
    case noSharedWiFi
}

/// Kartu panduan edukatif cerdas saat terjadi AP Isolation atau ketiadaan jaringan Wi-Fi bersama.
public struct FallbackCard: View {
    public let reason: FallbackReason
    public let onRetry: (() -> Void)?
    public let onDismiss: (() -> Void)?

    public init(
        reason: FallbackReason = .apIsolationDetected,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.reason = reason
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header: Icon & Judul
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.statusWarning)

                Text(reason == .apIsolationDetected ? "Koneksi Terisolasi (AP Isolation)" : "Tidak Ada Wi-Fi Bersama")
                    .font(Theme.Typography.headline)
                    .foregroundColor(.primary)

                Spacer()

                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Wi-Fi publik membatasi komunikasi lokal antar perangkat. Anda tetap dapat mentransfer file melalui salah satu jalur alternatif:")
                .font(Theme.Typography.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 2 Opsi Solusi Cepat
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // Opsi A: Hotspot HP
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    Image(systemName: "personalhotspot")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.samsungCyan)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Solusi Nirkabel: Mobile Hotspot")
                            .font(Theme.Typography.deviceTitle)
                            .foregroundColor(.primary)
                        Text("Nyalakan Hotspot di Samsung, lalu hubungkan Mac. (Kuota data seluler tidak terpakai).")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
                    .padding(.vertical, 2)

                // Opsi B: Kabel USB-C
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.statusSuccess)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Solusi Kabel: USB-C Tethering")
                            .font(Theme.Typography.deviceTitle)
                            .foregroundColor(.primary)
                        Text("Colok kabel USB-C ke Mac & aktifkan 'USB Tethering' di Samsung (Kecepatan hingga 800 MB/s).")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radii.button)
                    .fill(Color.primary.opacity(0.04))
            )

            // Footer Action
            if let onRetry = onRetry {
                HStack {
                    Spacer()
                    Button(action: {
                        TossShareHaptics.performSuccess()
                        onRetry()
                    }) {
                        Label("Periksa Ulang Koneksi", systemImage: "arrow.clockwise")
                            .font(Theme.Typography.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Theme.Colors.gradientBrand)
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radii.card)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radii.card)
                        .strokeBorder(Theme.Colors.statusWarning.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        )
    }
}
