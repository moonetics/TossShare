//
//  RadarMainView.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI
import UniformTypeIdentifiers
import TossShareCore

/// Jendela antarmuka utama TossShare dengan animasi radar konsentris dan drop zone berkas.
public struct RadarMainView: View {

    @ObservedObject public var registry: DeviceRegistry
    @ObservedObject public var advisor: ConnectivityAdvisor

    @State private var activeSession: TransferSession?
    @State private var targetDeviceName: String = ""
    @State private var activeSender: NearbySenderSession?

    @State private var isTargetedForDrop: Bool = false
    @State private var hoveredEndpointId: String?

    // Mock testing helper state
    @State private var isMockInjected: Bool = false

    public init(registry: DeviceRegistry, advisor: ConnectivityAdvisor) {
        self.registry = registry
        self.advisor = advisor
    }

    public var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2 - 30)

            ZStack {
                // 1. Latar Belakang Glassmorphism Native macOS
                backgroundLayer

                // 2. Cincin Radar Konsentris Bernapas
                radarRingsLayer(center: center)

                // 3. Node Mac Lokal di Titik Pusat
                localMacNode(center: center)

                // 4. Node Perangkat Target Samsung dalam Orbit Dinamis
                devicesOrbitLayer(center: center)

                // 5. Header Bar & Brand Info
                headerBar

                // 6. Kartu Fallback AP Isolation (Meluncur dari Bawah)
                if advisor.shouldShowFallbackCard {
                    VStack {
                        Spacer()
                        FallbackCard(
                            reason: .apIsolationDetected,
                            onDismiss: {
                                advisor.dismissFallbackCard()
                            }
                        )
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .zIndex(20)
                }

                // 7. Footer Status Bar
                if !advisor.shouldShowFallbackCard {
                    footerStatusBar
                }

                // 8. Modal Overlay Sesi Transfer Aktif
                if let session = activeSession {
                    transferModalOverlay(session: session)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(30)
                }
            }
            .frame(minWidth: 640, minHeight: 520)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: registry.devices.count)
            .animation(.easeInOut(duration: 0.3), value: activeSession != nil)
            .animation(.easeInOut(duration: 0.3), value: advisor.shouldShowFallbackCard)
        }
    }

    // MARK: - Subviews

    private var backgroundLayer: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                gradient: Gradient(colors: [
                    Theme.Colors.accentAirDrop.opacity(0.12),
                    Theme.Colors.accentSamsung.opacity(0.04),
                    Color.clear
                ]),
                center: .center,
                startRadius: 40,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }

    private func radarRingsLayer(center: CGPoint) -> some View {
        ZStack {
            PulsingRing(delay: 0.0)
                .frame(width: 210, height: 210)
                .position(center)

            PulsingRing(delay: 0.5)
                .frame(width: 300, height: 300)
                .position(center)

            PulsingRing(delay: 1.0)
                .frame(width: 390, height: 390)
                .position(center)
        }
    }

    private func localMacNode(center: CGPoint) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.surfaceCard)
                    .frame(width: 58, height: 58)
                    .overlay(Circle().stroke(Theme.Colors.borderSubtle, lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)

                Image(systemName: "laptopcomputer")
                    .font(.system(size: 26))
                    .foregroundColor(Theme.Colors.accentAirDrop)
            }

            Text("Mac Ini")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)
        }
        .position(center)
    }

    private func devicesOrbitLayer(center: CGPoint) -> some View {
        let nodePositions = RadarLayoutEngine.computePositions(
            for: registry.devices,
            center: center,
            innerRadius: 105,
            outerRadius: 195
        )

        return ForEach(registry.devices) { device in
            let pos = nodePositions.first(where: { $0.endpointId == device.endpointId })?.point ?? center

            DeviceAvatarNode(
                name: device.friendlyName,
                type: nodeType(for: device.deviceType),
                isHighlighted: hoveredEndpointId == device.endpointId
            )
            .position(pos)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: Binding(
                get: { hoveredEndpointId == device.endpointId },
                set: { isHovered in hoveredEndpointId = isHovered ? device.endpointId : nil }
            )) { providers in
                handleDroppedFiles(providers: providers, targetDevice: device)
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func nodeType(for deviceType: DeviceType) -> DeviceNodeType {
        switch deviceType {
        case .phone: return .phone
        case .tablet: return .tablet
        case .laptop: return .laptop
        case .unknown: return .unknown
        }
    }

    private var headerBar: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("TossShare")
                            .font(Theme.Typography.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.brandGradient)

                        StatusPillBadge(
                            text: "Quick Share",
                            style: .scanning,
                            isPulsing: true
                        )
                    }

                    Text("Tarik & lepas berkas ke avatar perangkat untuk mengirim")
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Tombol Mock Helper untuk Simulasi dan Diagnostik
                HStack(spacing: 8) {
                    Button(action: toggleMockDevices) {
                        Label(
                            isMockInjected ? "Hapus Mock" : "Tambah Mock",
                            systemImage: isMockInjected ? "trash" : "plus.circle"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button(action: toggleAPIsolationSimulation) {
                        Label(
                            advisor.shouldShowFallbackCard ? "Normal Wi-Fi" : "Tes AP Isolation",
                            systemImage: "wifi.exclamationmark"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)

            Spacer()
        }
    }

    private var footerStatusBar: some View {
        VStack {
            Spacer()
            HStack {
                let count = registry.devices.count
                if count == 0 {
                    StatusPillBadge(
                        text: "Memindai perangkat sekitar... Pastikan Quick Share aktif (Everyone 10 min)",
                        style: .scanning,
                        isPulsing: true
                    )
                } else {
                    StatusPillBadge(
                        text: "\(count) Perangkat Samsung Terdeteksi",
                        style: .success,
                        isPulsing: false
                    )
                }
            }
            .padding(.bottom, Theme.Spacing.md)
        }
    }

    private func transferModalOverlay(session: TransferSession) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { /* Prevent click through */ }

            VStack(spacing: Theme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mengirim ke \(targetDeviceName)")
                            .font(Theme.Typography.headline)
                            .foregroundColor(.primary)

                        if !session.authPin.isEmpty {
                            Text("Kode PIN Verifikasi: \(session.authPin)")
                                .font(Theme.Typography.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.Colors.accentSamsung)
                        }
                    }

                    Spacer()

                    Button(action: cancelActiveTransfer) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                TransferProgressBar(
                    fileName: session.items.first?.fileName ?? "Berkas",
                    progress: session.progress,
                    transferredBytes: session.transferredBytes,
                    totalBytes: max(1, session.totalBytes),
                    speedBytesPerSecond: session.speedBytesPerSecond,
                    onCancel: cancelActiveTransfer
                )
            }
            .padding(Theme.Spacing.lg)
            .frame(width: 440)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radii.sheet)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radii.sheet)
                            .stroke(Theme.Colors.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Actions

    private func handleDroppedFiles(providers: [NSItemProvider], targetDevice: PeerDevice) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let fileURL = url else { return }
            Task { @MainActor in
                self.startTransfer(fileURL: fileURL, to: targetDevice)
            }
        }
        return true
    }

    private func startTransfer(fileURL: URL, to device: PeerDevice) {
        let fileName = fileURL.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 1024

        let item = TransferItem(
            fileName: fileName,
            mimeType: "application/octet-stream",
            fileSize: fileSize,
            localURL: fileURL
        )

        self.targetDeviceName = device.friendlyName
        let sender = NearbySenderSession(peerEndpointId: device.endpointId, items: [item])
        self.activeSender = sender
        self.activeSession = sender.session

        TossShareHaptics.performDropSnapped()

        Task {
            sender.onProgressUpdate = { updatedSession in
                Task { @MainActor in
                    self.activeSession = updatedSession
                }
            }

            sender.onStateChange = { updatedSession in
                Task { @MainActor in
                    self.activeSession = updatedSession
                    if updatedSession.state == .completed {
                        TossShareHaptics.performSuccess()
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        self.activeSession = nil
                        self.activeSender = nil
                    }
                }
            }

            do {
                try await sender.start(host: device.ipAddress, port: device.port)
            } catch {
                Task { @MainActor in
                    TossShareHaptics.performWarning()
                    self.activeSession = nil
                    self.activeSender = nil
                }
            }
        }
    }

    private func cancelActiveTransfer() {
        activeSender?.cancel()
        activeSession = nil
        activeSender = nil
        TossShareHaptics.performWarning()
    }

    private func toggleMockDevices() {
        if isMockInjected {
            registry.clearAll()
            isMockInjected = false
        } else {
            for peer in MockDeviceSeeder.defaultPeers {
                registry.registerOrUpdate(device: peer)
            }
            isMockInjected = true
        }
    }

    private func toggleAPIsolationSimulation() {
        advisor.simulateAPIsolation(enabled: !advisor.shouldShowFallbackCard)
    }
}
