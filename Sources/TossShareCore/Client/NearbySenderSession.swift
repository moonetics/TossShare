//
//  NearbySenderSession.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import Network
import CryptoKit

final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFired = false

    /// Mengembalikan true HANYA pada pemanggilan pertama. Pemanggilan selanjutnya selalu false.
    func fireOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasFired { return false }
        hasFired = true
        return true
    }
}

/// Mengelola pengiriman serial ke NWConnection secara thread-safe, mencegah race condition pada sendSeq kripto dan paket stream.
private actor OutboundWireSender {
    private let connection: NWConnection
    private let engine: QuickShareProtocolEngine

    init(connection: NWConnection, engine: QuickShareProtocolEngine) {
        self.connection = connection
        self.engine = engine
    }

    func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let err = error {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func sendKeepAlive(ack: Bool = false) async throws {
        let data = try engine.makeKeepAliveFrame(ack: ack)
        let framed = QuickShareProtocolEngine.encodeLengthPrefixed(data)
        try await sendRaw(framed)
    }

    func sendFileChunk(
        payloadId: Int64,
        totalSize: Int64,
        offset: Int64,
        chunkData: Data,
        isLast: Bool,
        fileName: String? = nil
    ) async throws {
        let chunkPacket = try engine.makeFileChunkFrame(
            payloadId: payloadId,
            totalSize: totalSize,
            offset: offset,
            chunkData: chunkData,
            isLast: isLast,
            fileName: fileName
        )
        let framed = QuickShareProtocolEngine.encodeLengthPrefixed(chunkPacket)
        try await sendRaw(framed)
    }

    func sendTransferSetup(frame: Sharing_Nearby_Frame) async throws {
        let (data1, data2) = try engine.makeTransferSetupBytesFrames(frame: frame)
        try await sendRaw(QuickShareProtocolEngine.encodeLengthPrefixed(data1))
        try await sendRaw(QuickShareProtocolEngine.encodeLengthPrefixed(data2))
    }

    func sendDisconnection() async throws {
        let discData = try engine.makeDisconnectionFrame()
        let framed = QuickShareProtocolEngine.encodeLengthPrefixed(discData)
        try await sendRaw(framed)
    }
}

/// Mengelola sesi pengiriman berkas dari Mac ke perangkat Samsung target (Client mode).
public final class NearbySenderSession: @unchecked Sendable {

    public private(set) var session: TransferSession
    public var targetDevice: PeerDevice?
    public var targetEndpoint: NWEndpoint?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.tossshare.sender.session", qos: .userInitiated)

    public var onProgressUpdate: (@Sendable (TransferSession) -> Void)?
    public var onStateChange: (@Sendable (TransferSession) -> Void)?

    public init(peerEndpointId: String, items: [TransferItem]) {
        let totalSize = items.reduce(0) { $0 + $1.fileSize }
        self.session = TransferSession(
            peerEndpointId: peerEndpointId,
            direction: .outgoing,
            state: .idle,
            totalBytes: totalSize,
            items: items
        )
    }

    /// Inisialisasi cepat dengan entitas PeerDevice untuk pengiriman berkas.
    public convenience init(device: PeerDevice, items: [TransferItem]) {
        self.init(peerEndpointId: device.endpointId, items: items)
        self.targetDevice = device
        self.targetEndpoint = device.endpoint
    }

    /// Inisialisasi cepat untuk pengiriman teks atau tautan clipboard ke perangkat Samsung berdasarkan endpoint ID.
    public convenience init(peerEndpointId: String, clipboardText: String, title: String = "Teks Clipboard") {
        let textItem = TransferItem(
            fileName: clipboardText,
            mimeType: "text/plain",
            fileSize: Int64(clipboardText.utf8.count),
            localURL: nil,
            sha256Checksum: nil
        )
        self.init(peerEndpointId: peerEndpointId, items: [textItem])
    }

    /// Inisialisasi cepat dengan entitas PeerDevice untuk pengiriman teks clipboard.
    public convenience init(device: PeerDevice, clipboardText: String, title: String = "Teks Clipboard") {
        self.init(peerEndpointId: device.endpointId, clipboardText: clipboardText, title: title)
        self.targetDevice = device
        self.targetEndpoint = device.endpoint
    }

    /// Mengirim teks clipboard langsung pada instance sesi ini.
    /// Jika targetDevice belum diatur, otomatis mencari perangkat yang cocok di DeviceRegistry berdasarkan endpointId.
    public func sendClipboardText(text: String) async throws {
        let textItem = TransferItem(
            fileName: text,
            mimeType: "text/plain",
            fileSize: Int64(text.utf8.count),
            localURL: nil,
            sha256Checksum: nil
        )
        self.session = TransferSession(
            peerEndpointId: self.session.peerEndpointId,
            direction: .outgoing,
            state: .idle,
            totalBytes: Int64(text.utf8.count),
            items: [textItem]
        )

        if let targetDevice {
            try await start(device: targetDevice)
            return
        }

        if let targetEndpoint {
            try await start(endpoint: targetEndpoint)
            return
        }

        // Resolusi otomatis via DeviceRegistry jika target belum diset
        let resolved = await MainActor.run {
            DeviceRegistry.shared.devices.first(where: { $0.endpointId == self.session.peerEndpointId })
        }

        if let resolved {
            self.targetDevice = resolved
            try await start(device: resolved)
            return
        }

        throw SenderSessionError.screenLockedOrUnreachable
    }

    /// Mengirim teks clipboard langsung ke perangkat tujuan pada instance sesi ini.
    public func sendClipboardText(_ text: String, to device: PeerDevice) async throws {
        self.targetDevice = device
        try await sendClipboardText(text: text)
    }

    /// Helper statis untuk mengirimkan teks clipboard secara instan ke entitas PeerDevice.
    public static func sendClipboardText(_ text: String, to device: PeerDevice) async throws -> NearbySenderSession {
        let sender = NearbySenderSession(device: device, clipboardText: text)
        try await sender.sendClipboardText(text: text)
        return sender
    }

    deinit {
        cancel()
    }

    // MARK: - Transfer Orchestration

    /// Menjalankan pengiriman langsung ke entitas PeerDevice (otomatis memilih NWEndpoint mDNS jika tersedia).
    public func start(device: PeerDevice) async throws {
        if let endpoint = device.endpoint {
            try await start(endpoint: endpoint)
        } else {
            try await start(host: device.ipAddress, port: device.port)
        }
    }

    /// Menjalankan pengiriman langsung ke NWEndpoint native (Bonjour service mDNS Samsung).
    public func start(endpoint: NWEndpoint) async throws {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let nwConn = NWConnection(to: endpoint, using: params)
        try await runTransferLoop(connection: nwConn)
    }

    /// Menjalankan pengiriman ke host string dan port numerik (fallback Wi-Fi biasa / IP statis).
    public func start(host: String, port: Int) async throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw SenderSessionError.invalidPort(port)
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let nwConn = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: params)
        try await runTransferLoop(connection: nwConn)
    }

    // MARK: - Core Quick Share Wire Transfer Loop

    private func runTransferLoop(connection nwConn: NWConnection) async throws {
        self.connection = nwConn

        do {
            try await executeTransferProtocol(connection: nwConn)
        } catch {
            print("❌ \u{001B}[1;31m[SEND-CLIENT-ERROR]\u{001B}[0m Pengiriman gagal ke '\(session.peerEndpointId)': \(error), Deskripsi: \(error.localizedDescription)")
            if !session.state.isTerminal {
                session.fail(with: error.localizedDescription)
                notifyStateChange()
            }
            throw error
        }
    }

    private func executeTransferProtocol(connection nwConn: NWConnection) async throws {
        // 1. Inisiasi Koneksi TCP dengan Timeout 10 Detik
        print("🚀 \u{001B}[1;35m[SEND-CLIENT]\u{001B}[0m [Langkah 1/10] Menginisiasi koneksi TCP ke target: \(nwConn.endpoint)...")
        try session.transition(to: .connecting)
        notifyStateChange()

        let flag = AtomicFlag()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    nwConn.stateUpdateHandler = { newState in
                        switch newState {
                        case .ready:
                            if flag.fireOnce() {
                                print("🟢 \u{001B}[1;32m[SEND-CLIENT]\u{001B}[0m Soket TCP terhubung (.ready)")
                                continuation.resume()
                            }
                        case .failed(let err):
                            if flag.fireOnce() {
                                print("❌ \u{001B}[1;31m[SEND-CLIENT]\u{001B}[0m Soket TCP gagal (.failed): \(err)")
                                continuation.resume(throwing: err)
                            }
                        case .cancelled:
                            if flag.fireOnce() {
                                continuation.resume(throwing: SenderSessionError.connectionCancelled)
                            }
                        case .waiting(let err):
                            print("⚠️ \u{001B}[1;33m[SEND-CLIENT]\u{001B}[0m Soket TCP waiting: \(err)")
                        default:
                            break
                        }
                    }
                    nwConn.start(queue: self.queue)
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10s Timeout
                if flag.fireOnce() {
                    nwConn.cancel()
                    print("⏱️ \u{001B}[1;31m[SEND-CLIENT]\u{001B}[0m Koneksi TCP timeout (10 detik)")
                    throw SenderSessionError.connectionTimeout
                }
            }

            // Tunggu tugas pertama yang selesai (sukses terhubung atau timeout)
            try await group.next()
            group.cancelAll()
        }

        let engine = QuickShareProtocolEngine()

        // 2. Kirim ConnectionRequestFrame (OfflineFrame Google Nearby Connections dengan mediums = [.wifiLan])
        let senderLocalEndpointId = String((0..<4).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        print("📤 \u{001B}[1;35m[SEND-CLIENT]\u{001B}[0m [Langkah 2/10] Mengirim ConnectionRequestFrame (client endpoint: \(senderLocalEndpointId), target: \(session.peerEndpointId))...")
        let reqData = try QuickShareProtocolEngine.makeConnectionRequestFrame(
            endpointId: senderLocalEndpointId,
            endpointName: Host.current().localizedName ?? "Mac"
        )
        try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(reqData))

        // 3. Jabat Tangan UKEY2 (Curve P-256 ECDH)
        try session.transition(to: .authenticating)
        notifyStateChange()

        print("🔑 \u{001B}[1;33m[SEND-CLIENT]\u{001B}[0m [Langkah 3/10] Mengirim UKEY2 ClientInit...")
        let clientInitData = try engine.makeUkey2ClientInitFrame()
        try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(clientInitData))

        let serverInitPacket = try await receiveLengthPrefixedData()
        print("🔑 \u{001B}[1;33m[SEND-CLIENT]\u{001B}[0m Menerima UKEY2 ServerInit (\(serverInitPacket.count) bytes). Memverifikasi...")
        try engine.processUkey2ServerInit(serverInitRawData: serverInitPacket)

        if let pin = engine.authPin {
            session.authPin = pin
            print("🔑 \u{001B}[1;33m[SEND-CLIENT]\u{001B}[0m PIN Verifikasi UKEY2: \u{001B}[1;37m\(pin)\u{001B}[0m")
            notifyStateChange()
        }

        if let finishData = engine.ukeyClientFinishData {
            try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(finishData))
            print("🔑 \u{001B}[1;33m[SEND-CLIENT]\u{001B}[0m Mengirim UKEY2 ClientFinish")
        }

        let acceptFrame = try QuickShareProtocolEngine.makeConnectionResponseAcceptFrame()
        try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(acceptFrame))

        let peerRespData = try await receiveLengthPrefixedData()
        let peerOffline = try Location_Nearby_Connections_OfflineFrame(serializedData: peerRespData)
        guard peerOffline.v1.type == .connectionResponse,
              peerOffline.v1.connectionResponse.response == .accept else {
            print("❌ \u{001B}[1;31m[SEND-CLIENT]\u{001B}[0m Perangkat target menolak jabat tangan awal")
            throw SenderSessionError.connectionRejected
        }
        print("🤝 \u{001B}[1;32m[SEND-CLIENT]\u{001B}[0m [Langkah 4/10] ConnectionResponse ACCEPT saling terverifikasi")

        // 4. Inisialisasi Wire Sender & Heartbeat Keep-Alive (Setiap 10 Detik)
        let outboundSender = OutboundWireSender(connection: nwConn, engine: engine)
        let keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self = self, !Task.isCancelled else { break }
                do {
                    try await outboundSender.sendKeepAlive(ack: false)
                } catch {
                    #if DEBUG
                    print("[NearbySenderSession] Heartbeat keep-alive error: \(error)")
                    #endif
                    break
                }
            }
        }
        defer {
            keepAliveTask.cancel()
        }

        // 5. Pertukaran Kunci Terpasang (PairedKey Encryption & Result) via SecureChannel
        print("🔐 \u{001B}[1;35m[SEND-CLIENT]\u{001B}[0m [Langkah 5/10] Mengirim PairedKey Encryption & Result...")
        let pKeyFrame = QuickShareProtocolEngine.makePairedKeyEncryptionFrame()
        try await outboundSender.sendTransferSetup(frame: pKeyFrame)

        _ = try await receiveSharingFrame(using: engine, sender: outboundSender)

        let pResultFrame = QuickShareProtocolEngine.makePairedKeyResultFrame()
        try await outboundSender.sendTransferSetup(frame: pResultFrame)

        _ = try await receiveSharingFrame(using: engine, sender: outboundSender)
        print("🔐 \u{001B}[1;35m[SEND-CLIENT]\u{001B}[0m PairedKey exchange selesai")

        // 6. Kirim Metadata Berkas atau Teks (IntroductionFrame: Data + lastChunk)
        let isTextTransfer = session.items.first?.mimeType == "text/plain" && session.items.first?.localURL == nil
        let introFrame: Sharing_Nearby_Frame
        let payloadIds: [Int64]
        let textPayloadId: Int64

        if isTextTransfer, let textItem = session.items.first {
            let (tFrame, pId) = QuickShareProtocolEngine.makeTextIntroductionFrame(text: textItem.fileName, title: "Teks Clipboard")
            introFrame = tFrame
            payloadIds = [pId]
            textPayloadId = pId
            print("📄 \u{001B}[1;34m[SEND-CLIENT]\u{001B}[0m [Langkah 6/10] Mengirim IntroductionFrame: Teks Clipboard (\(textItem.fileName.count) karakter)...")
        } else {
            let (fFrame, pIds) = QuickShareProtocolEngine.makeIntroductionFrame(items: session.items)
            introFrame = fFrame
            payloadIds = pIds
            textPayloadId = 0
            print("📄 \u{001B}[1;34m[SEND-CLIENT]\u{001B}[0m [Langkah 6/10] Mengirim IntroductionFrame: \(session.items.count) berkas (\(session.totalBytes) bytes)...")
        }

        try await outboundSender.sendTransferSetup(frame: introFrame)

        // 7. Tunggu Persetujuan Pengguna Samsung (Prompt Native One UI di Layar Ponsel)
        print("📱 \u{001B}[1;33m[SEND-CLIENT]\u{001B}[0m [Langkah 7/10] Menunggu persetujuan pengguna di layar ponsel Samsung...")
        try session.transition(to: .waitingAcceptance)
        notifyStateChange()

        let sharingFrame = try await receiveSharingFrame(using: engine, sender: outboundSender)

        if sharingFrame.v1.type == .cancel {
            print("⛔ \u{001B}[1;33m[SEND-CLIENT]\u{001B}[0m Pengiriman dibatalkan oleh pengguna Samsung.")
            session.fail(with: "Pengiriman dibatalkan oleh pengguna Samsung.")
            notifyStateChange()
            throw SenderSessionError.transferRejected
        }

        guard sharingFrame.v1.type == .response else {
            print("❌ \u{001B}[1;31m[SEND-CLIENT]\u{001B}[0m Frame respon tidak terduga: \(sharingFrame.v1.type)")
            throw SenderSessionError.unexpectedFrame(expected: .acceptance, actual: .acceptance)
        }

        switch sharingFrame.v1.connectionResponse.status {
        case .accept:
            print("✅ \u{001B}[1;32m[SEND-CLIENT]\u{001B}[0m Persetujuan DITERIMA oleh ponsel Samsung!")
        case .notEnoughSpace:
            print("❌ \u{001B}[1;31m[SEND-CLIENT]\u{001B}[0m Memori ponsel Samsung penuh")
            session.fail(with: SenderSessionError.storageFull.localizedDescription)
            notifyStateChange()
            throw SenderSessionError.storageFull
        case .timedOut:
            print("⏱️ \u{001B}[1;31m[SEND-CLIENT]\u{001B}[0m Waktu persetujuan ponsel Samsung habis")
            session.fail(with: SenderSessionError.transferTimedOut.localizedDescription)
            notifyStateChange()
            throw SenderSessionError.transferTimedOut
        case .reject:
            print("⛔ \u{001B}[1;33m[SEND-CLIENT]\u{001B}[0m Permintaan transfer ditolak oleh ponsel Samsung")
            session.fail(with: SenderSessionError.transferRejected.localizedDescription)
            notifyStateChange()
            throw SenderSessionError.transferRejected
        default:
            print("❌ \u{001B}[1;31m[SEND-CLIENT]\u{001B}[0m Permintaan transfer ditolak (\(sharingFrame.v1.connectionResponse.status))")
            session.fail(with: "Permintaan transfer ditolak oleh perangkat target.")
            notifyStateChange()
            throw SenderSessionError.transferRejected
        }

        // 8. Pengaliran Berkas Nyata (Streaming 512 KB Chunks) atau Teks
        print("📦 \u{001B}[1;36m[SEND-CLIENT]\u{001B}[0m [Langkah 8/10] Memulai transmisi chunk data...")
        try session.transition(to: .transferring)
        notifyStateChange()

        if isTextTransfer, let textItem = session.items.first {
            let textData = textItem.fileName.data(using: .utf8) ?? Data()
            let totalSize = Int64(textData.count)
            try await outboundSender.sendFileChunk(
                payloadId: textPayloadId,
                totalSize: totalSize,
                offset: 0,
                chunkData: textData,
                isLast: false
            )
            try await outboundSender.sendFileChunk(
                payloadId: textPayloadId,
                totalSize: totalSize,
                offset: totalSize,
                chunkData: Data(),
                isLast: true
            )
            session.updateProgress(
                transferredBytes: totalSize,
                speedBytesPerSecond: 0
            )
            onProgressUpdate?(session)
            print("📋 \u{001B}[1;32m[SEND-CLIENT]\u{001B}[0m Teks clipboard berhasil dikirim!")
        } else {
            let startTime = Date()
            var totalBytesStreamed: Int64 = 0

            for (index, item) in session.items.enumerated() {
                guard let localURL = item.localURL else { continue }
                let payloadId = (index < payloadIds.count) ? payloadIds[index] : Int64.random(in: 1_000_000...Int64.max)
                let fileHandle = try FileHandle(forReadingFrom: localURL)
                defer { try? fileHandle.close() }

                let chunkSize = 512 * 1024 // 512 KB
                var offset: Int64 = 0
                let fileSize = item.fileSize
                print("📤 \u{001B}[1;36m[SEND-CLIENT]\u{001B}[0m Mengirim berkas [\(index + 1)/\(session.items.count)]: '\(item.fileName)' (\(fileSize) bytes)...")

                while offset < fileSize {
                    let toRead = min(chunkSize, Int(fileSize - offset))
                    let chunkData = fileHandle.readData(ofLength: toRead)
                    if chunkData.isEmpty { break }

                    let currentOffset = offset
                    offset += Int64(chunkData.count)
                    totalBytesStreamed += Int64(chunkData.count)

                    try await outboundSender.sendFileChunk(
                        payloadId: payloadId,
                        totalSize: fileSize,
                        offset: currentOffset,
                        chunkData: chunkData,
                        isLast: false,
                        fileName: item.fileName
                    )

                    // Hitung kecepatan transfer rata-rata
                    let elapsed = Date().timeIntervalSince(startTime)
                    let speed = elapsed > 0 ? Double(totalBytesStreamed) / elapsed : 0

                    session.updateProgress(
                        transferredBytes: totalBytesStreamed,
                        speedBytesPerSecond: speed
                    )
                    onProgressUpdate?(session)
                }

                // Kirim frame sinyal EOF (flags = 1, body kosong, offset = fileSize)
                try await outboundSender.sendFileChunk(
                    payloadId: payloadId,
                    totalSize: fileSize,
                    offset: fileSize,
                    chunkData: Data(),
                    isLast: true,
                    fileName: item.fileName
                )
                print("🏁 \u{001B}[1;32m[SEND-CLIENT]\u{001B}[0m Berkas '\(item.fileName)' selesai dialirkan")
            }
        }

        // 9. Jeda Drain 0.5 Detik (BATASAN TEGAS: Receiver memproses EOF tuntas sebelum socket ditutup)
        print("⏳ \u{001B}[1;34m[SEND-CLIENT]\u{001B}[0m [Langkah 9/10] Melakukan buffer drain 0.5 detik...")
        try await Task.sleep(nanoseconds: 500_000_000)

        // 10. Selesaikan Sesi dengan DisconnectionFrame
        print("🏁 \u{001B}[1;32m[SEND-CLIENT]\u{001B}[0m [Langkah 10/10] Mengirim DisconnectionFrame & Selesai!")
        try? await outboundSender.sendDisconnection()

        try session.transition(to: .completed)
        notifyStateChange()
    }

    /// Membatalkan sesi transfer secara aktif.
    public func cancel() {
        if !session.state.isTerminal {
            try? session.transition(to: .cancelled)
            notifyStateChange()
        }
        connection?.cancel()
        connection = nil
    }

    // MARK: - Low-Level Network Helpers

    private func sendData(_ data: Data) async throws {
        guard let conn = connection else { throw SenderSessionError.connectionNotOpen }
        return try await withCheckedThrowingContinuation { continuation in
            conn.send(content: data, completion: .contentProcessed { error in
                if let err = error {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveLengthPrefixedData() async throws -> Data {
        guard let conn = connection else { throw SenderSessionError.connectionNotOpen }

        // 1. Baca 4-byte header panjang Big-Endian dengan bit-shift aman
        let lengthHeader = try await receiveExactBytes(count: 4, on: conn)
        let payloadLength = (UInt32(lengthHeader[0]) << 24) |
                            (UInt32(lengthHeader[1]) << 16) |
                            (UInt32(lengthHeader[2]) << 8)  |
                            UInt32(lengthHeader[3])

        guard payloadLength < 10 * 1024 * 1024 else {
            throw SenderSessionError.invalidHandshakePayload
        }

        // 2. Baca muatan payload lengkap
        let payload = try await receiveExactBytes(count: Int(payloadLength), on: conn)
        return payload
    }

    private func receiveSharingFrame(
        using engine: QuickShareProtocolEngine,
        sender: OutboundWireSender? = nil
    ) async throws -> Sharing_Nearby_Frame {
        var buffer = Data()
        while true {
            let rawSmsg = try await receiveLengthPrefixedData()
            let offline = try engine.decryptSecureMessage(rawSmsg)

            if offline.v1.type == .disconnection {
                session.fail(with: "Koneksi diputus oleh perangkat target.")
                notifyStateChange()
                throw SenderSessionError.transferRejected
            }

            if offline.v1.type == .keepAlive {
                if let sender = sender {
                    try? await sender.sendKeepAlive(ack: true)
                }
                continue
            }

            guard offline.v1.type == .payloadTransfer else {
                continue
            }

            let chunk = offline.v1.payloadTransfer.payloadChunk
            buffer.append(chunk.body)

            if (chunk.flags & 1) == 1 {
                return try Sharing_Nearby_Frame(serializedData: buffer)
            }
        }
    }

    private func receiveExactBytes(count: Int, on conn: NWConnection) async throws -> Data {
        if count == 0 { return Data() }
        var buffer = Data()
        while buffer.count < count {
            let needed = count - buffer.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                let flag = AtomicFlag()
                conn.receive(minimumIncompleteLength: 1, maximumLength: needed) { content, _, isComplete, error in
                    guard flag.fireOnce() else { return }
                    if let err = error {
                        continuation.resume(throwing: err)
                    } else if let data = content, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: SenderSessionError.connectionClosedPrematurely)
                    } else {
                        continuation.resume(throwing: SenderSessionError.connectionClosedPrematurely)
                    }
                }
            }
            buffer.append(chunk)
        }
        return buffer
    }

    private func notifyStateChange() {
        onStateChange?(session)
    }
}

public enum SenderSessionError: Error, Equatable, Sendable, LocalizedError {
    case invalidPort(Int)
    case connectionNotOpen
    case connectionCancelled
    case connectionClosedPrematurely
    case invalidHandshakePayload
    case cryptoKeyDerivationFailed
    case unexpectedFrame(expected: NearbyFrameType, actual: NearbyFrameType)
    case transferRejected
    case connectionRejected
    case connectionTimeout
    case storageFull
    case transferTimedOut
    case screenLockedOrUnreachable

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Nomor port target (\(port)) tidak valid."
        case .connectionNotOpen:
            return "Koneksi jaringan belum terbuka."
        case .connectionCancelled:
            return "Pengiriman dibatalkan oleh pengguna."
        case .connectionClosedPrematurely:
            return "Koneksi terputus tiba-tiba oleh perangkat target."
        case .invalidHandshakePayload:
            return "Format data jabat tangan tidak valid atau sesi terputus."
        case .cryptoKeyDerivationFailed:
            return "Gagal melakukan verifikasi kunci enkripsi UKEY2."
        case .unexpectedFrame(let exp, let act):
            return "Menerima frame tidak sesuai (ekspektasi: \(exp), aktual: \(act))."
        case .transferRejected:
            return "Permintaan transfer ditolak di layar Samsung."
        case .connectionRejected:
            return "Koneksi ditolak oleh perangkat Samsung."
        case .connectionTimeout:
            return "Koneksi timeout setelah 10 detik. Pastikan Quick Share aktif."
        case .storageFull:
            return "Ruang penyimpanan ponsel tujuan tidak mencukupi."
        case .transferTimedOut:
            return "Permintaan transfer kedaluwarsa di layar Samsung."
        case .screenLockedOrUnreachable:
            return "Ponsel terkunci atau tidak dapat dijangkau. Pastikan layar HP menyala dan kunci layar terbuka."
        }
    }
}
