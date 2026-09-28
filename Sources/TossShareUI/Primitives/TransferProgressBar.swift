//
//  TransferProgressBar.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI

/// Komponen progress bar transfer dengan indikator byte, persentase, dan kecepatan transmisi (MB/s).
public struct TransferProgressBar: View {
    public let fileName: String
    public let progress: Double // 0.0 s/d 1.0
    public let transferredBytes: Int64
    public let totalBytes: Int64
    public let speedBytesPerSecond: Double
    public let onCancel: (() -> Void)?

    public init(
        fileName: String,
        progress: Double,
        transferredBytes: Int64,
        totalBytes: Int64,
        speedBytesPerSecond: Double,
        onCancel: (() -> Void)? = nil
    ) {
        self.fileName = fileName
        self.progress = max(0.0, min(1.0, progress))
        self.transferredBytes = transferredBytes
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Header: Nama File & Tombol Batal
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(Theme.Colors.samsungCyan)
                    .font(.system(size: 13))

                Text(fileName)
                    .font(Theme.Typography.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let onCancel = onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Batalkan Transfer")
                }
            }

            // Track Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Latar Belakang Track
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 7)

                    // Fill Progress Aktif
                    Capsule()
                        .fill(Theme.Colors.gradientBrand)
                        .frame(width: max(7, geo.size.width * CGFloat(progress)), height: 7)
                        .animation(.linear(duration: 0.2), value: progress)
                }
            }
            .frame(height: 7)

            // Footer: Bytes terkirim, Kecepatan, Persentase
            HStack {
                Text("\(Theme.Formatters.formatBytes(transferredBytes)) / \(Theme.Formatters.formatBytes(totalBytes))")
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(Theme.Formatters.formatSpeed(speedBytesPerSecond))
                    .font(Theme.Typography.monospaceSpeed)
                    .foregroundColor(Theme.Colors.statusTransferring)

                Text("•")
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)

                Text("\(Int(progress * 100))%")
                    .font(Theme.Typography.monospaceSpeed)
                    .foregroundColor(.primary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radii.card)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radii.card)
                        .strokeBorder(Theme.Colors.borderHairline, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
    }
}
