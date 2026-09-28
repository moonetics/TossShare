//
//  MenuBarPopoverView.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI
import UniformTypeIdentifiers
import TossShareCore

/// Popover ringkas dari status item menu bar macOS yang menyediakan area drop cepat dan status perangkat.
public struct MenuBarPopoverView: View {

    @ObservedObject public var registry: DeviceRegistry
    @ObservedObject public var advisor: ConnectivityAdvisor
    public var onOpenRadarWindow: (() -> Void)?

    @State private var isTargetedForDrop: Bool = false

    public init(
        registry: DeviceRegistry,
        advisor: ConnectivityAdvisor,
        onOpenRadarWindow: (() -> Void)? = nil
    ) {
        self.registry = registry
        self.advisor = advisor
        self.onOpenRadarWindow = onOpenRadarWindow
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Header Status
            headerSection

            Divider()

            // Area Drop Zone Cepat
            quickDropZoneSection

            Divider()

            // Daftar Perangkat Sekitar
            nearbyDevicesSection

            Divider()

            // Footer Aksi
            footerActions
        }
        .padding(Theme.Spacing.md)
        .frame(width: 300)
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack {
            Image(systemName: "arrow.triangle.swap")
                .foregroundColor(Theme.Colors.accentAirDrop)

            Text("TossShare")
                .font(Theme.Typography.deviceTitle)
                .fontWeight(.bold)

            Spacer()

            if advisor.shouldShowFallbackCard {
                StatusPillBadge(type: .warning("AP Isolation"))
            } else {
                StatusPillBadge(type: .ready)
            }
        }
    }

    private var quickDropZoneSection: some View {
        VStack(spacing: 6) {
            Image(systemName: isTargetedForDrop ? "arrow.down.circle.fill" : "plus.circle")
                .font(.system(size: 24))
                .foregroundColor(isTargetedForDrop ? Theme.Colors.accentSamsung : .secondary)

            Text(isTargetedForDrop ? "Lepas untuk mengirim!" : "Tarik berkas ke sini")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radii.small)
                .strokeBorder(
                    isTargetedForDrop ? Theme.Colors.accentSamsung : Theme.Colors.borderSubtle,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5])
                )
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radii.small)
                        .fill(isTargetedForDrop ? Theme.Colors.accentSamsung.opacity(0.08) : Color.clear)
                )
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargetedForDrop) { providers in
            // Jika ada perangkat pertama, kirim ke perangkat tersebut
            if let firstDevice = registry.devices.first {
                return handleDroppedFile(providers: providers, targetDevice: firstDevice)
            }
            return false
        }
    }

    private var nearbyDevicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Perangkat Sekitar")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)

            if registry.devices.isEmpty {
                HStack {
                    Spacer()
                    Text("Belum ada perangkat terdeteksi")
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                    Spacer()
                }
            } else {
                ForEach(registry.devices.prefix(3)) { device in
                    HStack(spacing: 8) {
                        Image(systemName: deviceIconName(for: device.deviceType))
                            .foregroundColor(Theme.Colors.accentAirDrop)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.friendlyName)
                                .font(Theme.Typography.deviceTitle)
                                .lineLimit(1)

                            if let rssi = device.rssi {
                                Text("\(rssi) dBm")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var footerActions: some View {
        HStack {
            Button {
                onOpenRadarWindow?()
            } label: {
                Label("Buka Radar", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accentAirDrop)

            Spacer()

            Button("Keluar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func deviceIconName(for type: DeviceType) -> String {
        switch type {
        case .phone: return "iphone.gen3"
        case .tablet: return "ipad.gen2"
        case .laptop: return "laptopcomputer"
        case .unknown: return "display"
        }
    }

    private func handleDroppedFile(providers: [NSItemProvider], targetDevice: PeerDevice) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { _, _ in
            Task { @MainActor in
                TossShareHaptics.performDropSnapped()
            }
        }
        return true
    }
}
