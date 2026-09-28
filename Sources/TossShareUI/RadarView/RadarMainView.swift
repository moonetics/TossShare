//
//  RadarMainView.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI
import UniformTypeIdentifiers
import TossShareCore
import AppKit

/// Jendela antarmuka utama TossShare dengan animasi radar konsentris dan drop zone berkas.
public struct RadarMainView: View {

    @ObservedObject public var registry: DeviceRegistry
    @ObservedObject public var advisor: ConnectivityAdvisor
    @ObservedObject private var notificationManager = TransferNotificationManager.shared

    @State private var activeSession: TransferSession?
    @State private var targetDeviceName: String = ""
    @State private var activeSender: NearbySenderSession?

    @State private var isTargetedForDrop: Bool = false
    @State private var hoveredEndpointId: String?
    @State private var isShowingQRPairing: Bool = false

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

                // 8. In-App Fallback Modal Permintaan Transfer Masuk (Prioritas Tertinggi)
                if let incoming = notificationManager.fallbackIncomingSession,
                   let sender = notificationManager.fallbackSenderDevice {
                    incomingTransferModalOverlay(session: incoming, sender: sender)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(35)
                } else if let session = activeSession {
                    // 9. Modal Overlay Sesi Transfer Keluar Aktif
                    transferModalOverlay(session: session)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(30)
                }
            }
            .frame(minWidth: 640, minHeight: 520)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: registry.devices.count)
            .animation(.easeInOut(duration: 0.3), value: activeSession != nil)
            .animation(.easeInOut(duration: 0.3), value: advisor.shouldShowFallbackCard)
            .sheet(isPresented: $isShowingQRPairing) {
                QRPairingSheetView()
            }
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
            let displayName = registry.displayName(for: device)
            let isPrivacy = device.isPrivacyMode
            let subtitle = isPrivacy ? "Mode Privasi" : (device.ipAddress.isEmpty || device.ipAddress == "mDNS" ? "Siap Menerima" : device.ipAddress)

            DeviceAvatarNode(
                name: displayName,
                type: nodeType(for: device.deviceType),
                statusSubtitle: subtitle,
                isHighlighted: hoveredEndpointId == device.endpointId
            )
            .contextMenu {
                Button {
                    sendClipboardText(to: device)
                } label: {
                    let clip = NSPasteboard.general.string(forType: .string) ?? ""
                    let preview = clip.count > 25 ? String(clip.prefix(25)) + "..." : clip
                    if !preview.isEmpty {
                        Label("Kirim Teks: \"\(preview)\"", systemImage: "doc.on.clipboard")
                    } else {
                        Label("Kirim Teks Clipboard", systemImage: "doc.on.clipboard")
                    }
                }

                Button {
                    selectAndSendFiles(to: device)
                } label: {
                    Label("Kirim Berkas...", systemImage: "folder")
                }
            }
            .help(device.isPrivacyMode ? "Atur Quick Share ke 'Siapa saja' di HP agar nama lengkap muncul" : "")
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

                HStack(spacing: 8) {
                    // Tombol Fallback QR Pairing
                    Button(action: { isShowingQRPairing = true }) {
                        Label("QR Pairing", systemImage: "qrcode")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    // Tombol Mock Helper untuk Simulasi dan Diagnostik
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
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { /* Prevent click through */ }

            if session.state == .waitingAcceptance {
                waitingAcceptanceInteractiveCard(session: session)
            } else {
                standardTransferCard(session: session)
            }
        }
    }

    private func waitingAcceptanceInteractiveCard(session: TransferSession) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            // Ikon Smartphone Animasi dengan Halo Bercahaya
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentSamsung.opacity(0.15))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(Theme.Colors.surfaceCard)
                    .frame(width: 64, height: 64)
                    .overlay(Circle().stroke(Theme.Colors.accentSamsung, lineWidth: 2))

                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.Colors.accentSamsung)
            }
            .padding(.top, Theme.Spacing.sm)

            VStack(spacing: 6) {
                Text("Menunggu Persetujuan...")
                    .font(Theme.Typography.headline)
                    .fontWeight(.bold)

                Text("Buka kunci layar **\(targetDeviceName)**, lalu ketuk **'Terima'** pada dialog Quick Share ponsel.")
                    .font(Theme.Typography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.md)
            }

            if !session.authPin.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(Theme.Colors.accentSamsung)
                    Text("Kode PIN Verifikasi: \(session.authPin)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Theme.Colors.accentSamsung.opacity(0.12))
                        .overlay(Capsule().stroke(Theme.Colors.accentSamsung.opacity(0.35), lineWidth: 1))
                )
            }

            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Menunggu respons dari ponsel Samsung...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)

            Divider()

            Button(role: .cancel, action: cancelActiveTransfer) {
                Text("Batalkan Transfer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 420)
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

    private func standardTransferCard(session: TransferSession) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mengirim ke \(targetDeviceName)")
                        .font(Theme.Typography.headline)
                        .foregroundColor(.primary)

                    Text(transferStatusText(for: session))
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)

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

    private func transferStatusText(for session: TransferSession) -> String {
        switch session.state {
        case .connecting:
            return "Menghubungkan ke \(targetDeviceName)..."
        case .authenticating:
            return "Menjabat tangan enkripsi UKEY2..."
        case .waitingAcceptance:
            return "Menunggu Anda menekan 'Terima' di layar \(targetDeviceName)..."
        case .transferring:
            return "Mengalirkan berkas ke \(targetDeviceName)..."
        case .completed:
            return "Pengiriman Berhasil!"
        case .failed:
            return session.errorMessage ?? "Pengiriman Gagal"
        case .cancelled:
            return "Dibatalkan"
        case .idle:
            return "Menyiapkan berkas..."
        }
    }

    // MARK: - Actions

    private func handleDroppedFiles(providers: [NSItemProvider], targetDevice: PeerDevice) -> Bool {
        guard !providers.isEmpty else { return false }

        let group = DispatchGroup()
        let collector = URLCollector()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { group.leave() }
                if let fileURL = url {
                    collector.append(fileURL)
                }
            }
        }

        group.notify(queue: .main) {
            let flattened = FileItemCollector.flattenURLs(collector.getAll())
            guard !flattened.isEmpty else { return }
            self.startTransfer(fileURLs: flattened, to: targetDevice)
        }
        return true
    }

    private func startTransfer(fileURLs: [URL], to device: PeerDevice) {
        // Cari entitas perangkat teranyar di registry untuk menghindari ID mDNS kadaluwarsa
        let activeDevice = registry.devices.first(where: {
            $0.endpointId == device.endpointId ||
            (!device.ipAddress.isEmpty && device.ipAddress != "mDNS" && $0.ipAddress == device.ipAddress)
        }) ?? device

        let items = fileURLs.compactMap { url -> TransferItem? in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 1024
            return TransferItem(
                fileName: url.lastPathComponent,
                mimeType: "application/octet-stream",
                fileSize: size,
                localURL: url
            )
        }

        guard !items.isEmpty else { return }

        self.targetDeviceName = registry.displayName(for: activeDevice)
        let sender = NearbySenderSession(peerEndpointId: activeDevice.endpointId, items: items)
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
                try await sender.start(device: activeDevice)
            } catch {
                Task { @MainActor in
                    TossShareHaptics.performWarning()
                    self.activeSession = sender.session
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if self.activeSession?.state == .failed {
                        self.activeSession = nil
                        self.activeSender = nil
                    }
                }
            }
        }
    }

    private func sendClipboardText(to device: PeerDevice) {
        let activeDevice = registry.devices.first(where: {
            $0.endpointId == device.endpointId ||
            (!device.ipAddress.isEmpty && device.ipAddress != "mDNS" && $0.ipAddress == device.ipAddress)
        }) ?? device

        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }

        let item = TransferItem(
            fileName: text,
            mimeType: "text/plain",
            fileSize: Int64(text.utf8.count),
            localURL: nil
        )

        self.targetDeviceName = registry.displayName(for: activeDevice)
        let sender = NearbySenderSession(peerEndpointId: activeDevice.endpointId, items: [item])
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
                try await sender.start(device: activeDevice)
            } catch {
                Task { @MainActor in
                    TossShareHaptics.performWarning()
                    self.activeSession = sender.session
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if self.activeSession?.state == .failed {
                        self.activeSession = nil
                        self.activeSender = nil
                    }
                }
            }
        }
    }

    private func selectAndSendFiles(to device: PeerDevice) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        let displayName = registry.displayName(for: device)
        panel.prompt = "Kirim ke \(displayName)"

        if panel.runModal() == .OK {
            let flattened = FileItemCollector.flattenURLs(panel.urls)
            guard !flattened.isEmpty else { return }
            self.startTransfer(fileURLs: flattened, to: device)
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

    private func incomingTransferModalOverlay(session: TransferSession, sender: PeerDevice) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.accentAirDrop.opacity(0.15))
                            .frame(width: 48, height: 48)

                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Theme.Colors.accentAirDrop)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permintaan Transfer Masuk")
                            .font(Theme.Typography.headline)
                        Text("Dari: \(sender.friendlyName)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Divider()

                VStack(spacing: 6) {
                    let count = session.items.count
                    let sizeStr = ByteCountFormatter.string(fromByteCount: session.totalBytes, countStyle: .file)
                    Text("\(count) Berkas • \(sizeStr)")
                        .font(Theme.Typography.deviceTitle)
                        .fontWeight(.semibold)

                    if !session.authPin.isEmpty {
                        Text("PIN Verifikasi: \(session.authPin)")
                            .font(Theme.Typography.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.Colors.accentSamsung)
                    }
                }
                .padding(.vertical, 8)

                HStack(spacing: 12) {
                    Button("Tolak", role: .cancel) {
                        notificationManager.resolveDecision(sessionId: session.sessionId, accepted: false)
                        TossShareHaptics.performWarning()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button("Terima") {
                        notificationManager.resolveDecision(sessionId: session.sessionId, accepted: true)
                        TossShareHaptics.performSuccess()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.Colors.surfaceCard)
                    .shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 8)
            )
        }
    }
}

