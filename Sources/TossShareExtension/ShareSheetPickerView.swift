//
//  ShareSheetPickerView.swift
//  TossShareExtension
//
//  Created for TossShare for macOS.
//

import SwiftUI
import TossShareCore

/// Tampilan antarmuka native modal share sheet yang muncul saat pengguna memilih berkas di Finder > Share > TossShare.
public struct ShareSheetPickerView: View {
    public let itemURLs: [URL]
    public let onSend: (PeerDevice, [URL]) -> Void
    public let onCancel: () -> Void

    @State private var selectedDevice: PeerDevice?
    @State private var availableDevices: [PeerDevice] = []
    @State private var isSending: Bool = false
    @State private var sendProgress: Double = 0.0
    @State private var statusMessage: String = "Pilih perangkat Samsung tujuan"

    public init(
        itemURLs: [URL],
        onSend: @escaping (PeerDevice, [URL]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.itemURLs = itemURLs
        self.onSend = onSend
        self.onCancel = onCancel
    }

    private var totalSizeBytes: Int64 {
        itemURLs.reduce(0) { total, url in
            let res = try? url.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(res?.fileSize ?? 0)
        }
    }

    private var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("TossShare")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Kirim ke Samsung Quick Share")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Batal", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Divider()

            // File Information Card
            HStack(spacing: 12) {
                Image(systemName: itemURLs.count == 1 ? "doc.fill" : "doc.on.doc.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    if let first = itemURLs.first {
                        Text(itemURLs.count == 1 ? first.lastPathComponent : "\(first.lastPathComponent) dan \(itemURLs.count - 1) berkas lainnya")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text("\(itemURLs.count) berkas • \(formattedTotalSize)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal, 16)

            // Device Picker List
            VStack(alignment: .leading, spacing: 8) {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)

                if availableDevices.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Memindai perangkat sekitar...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(availableDevices) { device in
                                DeviceTargetCard(
                                    device: device,
                                    isSelected: selectedDevice?.endpointId == device.endpointId,
                                    onSelect: {
                                        selectedDevice = device
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }

            if isSending {
                VStack(spacing: 6) {
                    ProgressView(value: sendProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text("Mengirim...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
            }

            Divider()

            // Footer Send Button
            HStack {
                Spacer()

                Button(action: handleSend) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Kirim Berkas")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDevice == nil || isSending)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 420, height: 380)
        .onAppear {
            loadDiscoveredDevices()
        }
    }

    private func loadDiscoveredDevices() {
        // Ambil perangkat dari registry aktif atau muat mock perangkat terdekat
        let current = DeviceRegistry.shared.devices
        if !current.isEmpty {
            self.availableDevices = current
            self.selectedDevice = current.first
        } else {
            self.availableDevices = MockDeviceSeeder.defaultPeers
            self.selectedDevice = self.availableDevices.first
        }
    }

    private func handleSend() {
        guard let device = selectedDevice else { return }
        self.isSending = true
        self.statusMessage = "Menghubungkan ke \(device.friendlyName)..."
        self.sendProgress = 0.15

        onSend(device, itemURLs)
    }
}

/// Kartu pemilihan target perangkat pada Share Sheet
private struct DeviceTargetCard: View {
    let device: PeerDevice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.12))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )

                    Image(systemName: iconName(for: device.deviceType))
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? .blue : .primary)
                }

                Text(device.friendlyName)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                    .lineLimit(1)
                    .frame(width: 80)

                Text(device.deviceType.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconName(for type: DeviceType) -> String {
        switch type {
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .laptop: return "laptopcomputer"
        case .unknown: return "display"
        }
    }
}
