//
//  Phase1PreviewGallery.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI

/// Layar galeri showcase untuk memverifikasi seluruh komponen primitif dan token desain Phase 1.
public struct Phase1PreviewGallery: View {
    @State private var sampleProgress: Double = 0.65
    @State private var showFallback: Bool = true
    @State private var selectedDevice: String? = "Galaxy S24 Ultra"

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Header Brand
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.Colors.gradientBrand)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TossShare Design System")
                            .font(Theme.Typography.largeTitle)
                            .foregroundColor(.primary)

                        Text("Phase 1: Tokens & Primitive Components Preview")
                            .font(Theme.Typography.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    StatusPillBadge(type: .scanning)
                }

                Divider()

                // Bagian 1: Radar Waves & Device Avatar Nodes
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("1. Radar Concentric Waves & Device Avatar Nodes")
                        .font(Theme.Typography.headline)

                    ZStack {
                        // Background Radar Plate
                        RoundedRectangle(cornerRadius: Theme.Radii.card)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radii.card)
                                    .strokeBorder(Theme.Colors.borderHairline, lineWidth: 1)
                            )
                            .frame(height: 220)

                        // 3 Lingkaran Radar Gelombang
                        PulsingRing(delay: 0.0, maxScale: 2.2)
                        PulsingRing(delay: 0.6, maxScale: 2.6)
                        PulsingRing(delay: 1.2, maxScale: 3.0)

                        // Avatar Perangkat Target
                        HStack(spacing: Theme.Spacing.xl) {
                            DeviceAvatarNode(
                                name: "Galaxy S24 Ultra",
                                type: .phone,
                                statusSubtitle: "Siap Terima",
                                isHighlighted: selectedDevice == "Galaxy S24 Ultra"
                            ) {
                                selectedDevice = "Galaxy S24 Ultra"
                            }

                            DeviceAvatarNode(
                                name: "Galaxy Tab S9",
                                type: .tablet,
                                statusSubtitle: "192.168.1.108",
                                isHighlighted: selectedDevice == "Galaxy Tab S9"
                            ) {
                                selectedDevice = "Galaxy Tab S9"
                            }

                            DeviceAvatarNode(
                                name: "Galaxy Z Fold 6",
                                type: .phone,
                                statusSubtitle: "Tersambung",
                                isHighlighted: selectedDevice == "Galaxy Z Fold 6"
                            ) {
                                selectedDevice = "Galaxy Z Fold 6"
                            }
                        }
                    }
                    .frame(height: 220)
                }

                // Bagian 2: Transfer Progress Bar
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("2. Live Transfer Progress Bar")
                        .font(Theme.Typography.headline)

                    TransferProgressBar(
                        fileName: "Liburan_Bali_4K_60FPS.mov",
                        progress: sampleProgress,
                        transferredBytes: Int64(Double(1_450_000_000) * sampleProgress),
                        totalBytes: 1_450_000_000,
                        speedBytesPerSecond: 52_400_000, // 52.4 MB/s
                        onCancel: {
                            sampleProgress = 0.0
                        }
                    )
                }

                // Bagian 3: Status Badges Gallery
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("3. Semantic Status Badges")
                        .font(Theme.Typography.headline)

                    HStack(spacing: Theme.Spacing.sm) {
                        StatusPillBadge(type: .ready)
                        StatusPillBadge(type: .scanning)
                        StatusPillBadge(type: .transferring)
                        StatusPillBadge(type: .success)
                        StatusPillBadge(type: .warning("AP Isolation"))
                    }
                }

                // Bagian 4: Fallback Guidance Card
                if showFallback {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("4. Network Fallback Guidance Card (AP Isolation / Offline)")
                            .font(Theme.Typography.headline)

                        FallbackCard(
                            reason: .apIsolationDetected,
                            onRetry: {
                                showFallback = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showFallback = true
                                }
                            },
                            onDismiss: {
                                showFallback = false
                            }
                        )
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(minWidth: 540, minHeight: 620)
    }
}
