//
//  NearbyReceiverServer.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import Network
import CryptoKit
import AppKit
import UserNotifications

/// Tracker thread-safe untuk mengidentifikasi nama instance dan endpoint lokal milik server Mac sendiri.
public final class ActiveServerTracker: @unchecked Sendable {
    public static let shared = ActiveServerTracker()
    private let lock = NSLock()
    private var instanceNames = Set<String>()
    private var listeningPorts = Set<UInt16>()

    private init() {}

    public func register(instanceName: String, endpointId: String, port: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        instanceNames.insert(instanceName)
        instanceNames.insert(endpointId)
        listeningPorts.insert(port)
    }

    public func unregister(instanceName: String?, endpointId: String, port: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        if let name = instanceName {
            instanceNames.remove(name)
        }
        instanceNames.remove(endpointId)
        listeningPorts.remove(port)
    }

    public func isSelf(instanceNameOrEndpointId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return instanceNames.contains(instanceNameOrEndpointId)
    }

    public func isSelfPort(_ port: UInt16) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return listeningPorts.contains(port)
    }
}

/// Server penerima berkas (Samsung -> Mac) berbasis NWListener dengan dukungan UKEY2, staging aman, dan mDNS NetService native.
public final class NearbyReceiverServer: NSObject, NetServiceDelegate, @unchecked Sendable {

    public let port: UInt16
    public let friendlyName: String
    public private(set) var localEndpointId: String = "M4C1"
    public private(set) var activeMdnsInstanceName: String?

    private var listener: NWListener?
    private var mdnsService: NetService?
    private let queue = DispatchQueue(label: "com.tossshare.receiver.server", qos: .userInitiated)
    private let fileManager: TransferFileManager

    /// Handler persetujuan penerimaan berkas (memberikan kesempatan pengguna/UI menerima atau menolak).
    public var onRequestAcceptance: (@Sendable (TransferSession) async -> Bool)?
    public var onTransferCompleted: (@Sendable (TransferSession) -> Void)?
    public var onTransferFailed: (@Sendable (TransferSession, Error) -> Void)?
    public var onClipboardReceived: (@Sendable (String, String) -> Void)?

    public init(
        port: UInt16 = 44445,
        friendlyName: String = "Mac (TossShare)",
        fileManager: TransferFileManager = TransferFileManager()
    ) {
        self.port = port
        self.friendlyName = friendlyName
        self.fileManager = fileManager
        super.init()
    }

    deinit {
        stop()
    }

    // MARK: - Server Lifecycle

    /// Membuka server soket TCP lokal dan mendaftarkan layanan mDNS Quick Share.
    public func start() throws {
        guard listener == nil else { return }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ReceiverServerError.invalidPort(Int(port))
        }

        let newListener = try NWListener(using: params, on: nwPort)

        newListener.newConnectionHandler = { [weak self] newConnection in
            self?.handleIncomingConnection(newConnection)
        }

        newListener.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            switch newState {
            case .ready:
                print("🟢 \u{001B}[1;32m[RECV-SERVER]\u{001B}[0m Listener TCP siap mendengarkan pada port: \(self.port)")
                self.publishMDNSService()
            case .failed(let err):
                print("❌ \u{001B}[1;31m[RECV-SERVER]\u{001B}[0m Listener error: \(err)")
            case .cancelled:
                print("⚪ \u{001B}[1;37m[RECV-SERVER]\u{001B}[0m Listener dihentikan.")
            default:
                break
            }
        }

        newListener.start(queue: queue)
        self.listener = newListener
    }

    /// Mempublikasikan layanan mDNS Bonjour menggunakan NetService native Darwin/Foundation.
    private func publishMDNSService() {
        guard mdnsService == nil else { return }

        // Konfigurasi Publikasi mDNS Bonjour resmi Quick Share (10-byte Base64 URL-safe)
        let randomEndpointId = String((0..<4).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        self.localEndpointId = randomEndpointId
        let mdnsInstanceName = EndpointInfoParser.generateMdnsInstanceName(endpointId: randomEndpointId)
        self.activeMdnsInstanceName = mdnsInstanceName

        ActiveServerTracker.shared.register(instanceName: mdnsInstanceName, endpointId: randomEndpointId, port: port)

        let resolvedName = friendlyName.isEmpty ? (Host.current().localizedName ?? "MacBook Pro") : friendlyName
        let txtRecord = EndpointInfoParser.createRecord(friendlyName: resolvedName, deviceType: .laptop)

        let service = NetService(
            domain: "",
            type: TossShareCore.quickShareMDNSServiceType,
            name: mdnsInstanceName,
            port: Int32(port)
        )
        service.delegate = self
        let txtDict: [String: Data] = ["n": Data(txtRecord.utf8)]
        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))
        service.schedule(in: .main, forMode: .common)
        service.publish()
        self.mdnsService = service

        print("📡 \u{001B}[1;36m[RECV-SERVER]\u{001B}[0m NetService mDNS diterbitkan: '\(mdnsInstanceName)' (port: \(port), nama: '\(resolvedName)')")
    }

    /// Menghentikan server penerima dan membatalkan publikasi mDNS.
    public func stop() {
        if let service = mdnsService {
            service.stop()
            service.remove(from: .main, forMode: .common)
            service.delegate = nil
            self.mdnsService = nil
        }

        ActiveServerTracker.shared.unregister(instanceName: activeMdnsInstanceName, endpointId: localEndpointId, port: port)
        self.activeMdnsInstanceName = nil

        listener?.cancel()
        listener = nil
    }

    // MARK: - NetServiceDelegate

    public func netServiceDidPublish(_ sender: NetService) {
        print("✅ \u{001B}[1;32m[RECV-SERVER]\u{001B}[0m NetService mDNS aktif terdaftar: \(sender.name).\(sender.type)")
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        print("⚠️ \u{001B}[1;33m[RECV-SERVER]\u{001B}[0m NetService gagal terbit: \(errorDict)")
    }

    // MARK: - Connection Handler

    private func handleIncomingConnection(_ connection: NWConnection) {
        print("🔵 \u{001B}[1;34m[RECV-SERVER]\u{001B}[0m Koneksi TCP masuk diterima dari: \(connection.endpoint)")
        connection.start(queue: queue)

        Task {
            var activeStagingURL: URL?
            do {
                // 1. Connection Request Frame (OfflineFrame Google Nearby Connections)
                let connReqPacket = try await receiveLengthPrefixedData(from: connection)
                let connReqFrame = try Location_Nearby_Connections_OfflineFrame(serializedData: connReqPacket)
                let peerEndpointId = connReqFrame.v1.connectionRequest.endpointID.isEmpty ? "samsung_client" : connReqFrame.v1.connectionRequest.endpointID
                let rawPeerName = connReqFrame.v1.connectionRequest.endpointName
                let epInfo = connReqFrame.v1.connectionRequest.endpointInfo
                let peerName: String = {
                    if epInfo.count > 17 {
                        let nameLen = Int(epInfo[17])
                        if nameLen > 0 && epInfo.count >= 18 + nameLen,
                           let nameStr = String(data: epInfo.subdata(in: 18..<(18 + nameLen)), encoding: .utf8),
                           !nameStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return nameStr.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    if let parsed = try? EndpointInfoParser.parse(data: epInfo), !parsed.friendlyName.isEmpty {
                        return parsed.friendlyName
                    }
                    if rawPeerName.contains("\n") {
                        let candidate = rawPeerName.components(separatedBy: "\n").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return candidate.isEmpty ? rawPeerName : candidate
                    }
                    return rawPeerName
                }()
                print("📥 \u{001B}[1;36m[RECV-SERVER]\u{001B}[0m [Langkah 1/8] ConnectionRequestFrame diterima: peer='\(peerName)', id='\(peerEndpointId)'")

                if !peerName.isEmpty {
                    Task { @MainActor in
                        DeviceRegistry.shared.updateFriendlyName(forEndpointId: peerEndpointId, friendlyName: peerName)
                    }
                }

                // 2. UKEY2 Handshake: Baca ClientInit
                let clientInitPacket = try await receiveLengthPrefixedData(from: connection)
                let engine = QuickShareProtocolEngine(role: .receiver)
                let serverInitPacket = try engine.processUkey2ClientInit(clientInitRawData: clientInitPacket)
                print("🔑 \u{001B}[1;33m[RECV-SERVER]\u{001B}[0m [Langkah 2/8] UKEY2 ClientInit diverifikasi (\(clientInitPacket.count) B) -> Mengirim ServerInit (\(serverInitPacket.count) B)...")
                try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(serverInitPacket), on: connection)

                // 3. Baca ClientFinish & Turunkan Kunci Sesi
                let clientFinishPacket = try await receiveLengthPrefixedData(from: connection)
                try engine.processUkey2ClientFinish(clientFinishRawData: clientFinishPacket)

                guard let pin = engine.authPin else {
                    throw ReceiverServerError.keyDerivationFailed
                }
                print("🔑 \u{001B}[1;33m[RECV-SERVER]\u{001B}[0m [Langkah 3/8] UKEY2 Handshake selesai! Kunci sesi aktif. Kode PIN: \u{001B}[1;37m\(pin)\u{001B}[0m")

                // 4. Pertukaran Connection Response Frame
                let clientConnRespPacket = try await receiveLengthPrefixedData(from: connection)
                let clientConnResp = try Location_Nearby_Connections_OfflineFrame(serializedData: clientConnRespPacket)
                guard clientConnResp.v1.type == .connectionResponse,
                      clientConnResp.v1.connectionResponse.response == .accept else {
                    print("❌ \u{001B}[1;31m[RECV-SERVER]\u{001B}[0m Client menolak ConnectionResponse atau frame tidak terduga: \(clientConnResp.v1.type)")
                    throw ReceiverServerError.unexpectedFrame(expected: .acceptance, actual: .acceptance)
                }

                let serverConnResp = try QuickShareProtocolEngine.makeConnectionResponseAcceptFrame()
                try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(serverConnResp), on: connection)
                print("🤝 \u{001B}[1;32m[RECV-SERVER]\u{001B}[0m [Langkah 4/8] Pertukaran ConnectionResponse ACCEPT berhasil")

                // 5. Pertukaran Paired Key Encryption & Result
                _ = try await receiveSharingFrame(from: connection, using: engine)

                let srvPKey = QuickShareProtocolEngine.makePairedKeyEncryptionFrame()
                let (srvPKey1, srvPKey2) = try engine.makeTransferSetupBytesFrames(frame: srvPKey)
                try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(srvPKey1), on: connection)
                try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(srvPKey2), on: connection)

                _ = try await receiveSharingFrame(from: connection, using: engine)

                let srvPResult = QuickShareProtocolEngine.makePairedKeyResultFrame()
                let (srvPRes1, srvPRes2) = try engine.makeTransferSetupBytesFrames(frame: srvPResult)
                try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(srvPRes1), on: connection)
                try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(srvPRes2), on: connection)
                print("🔐 \u{001B}[1;35m[RECV-SERVER]\u{001B}[0m [Langkah 5-6/8] Pertukaran PairedKeyEncryption & Result selesai")

                // 6. Baca IntroductionFrame (Manifest Berkas: Data + lastChunk)
                let introSharing = try await receiveSharingFrame(from: connection, using: engine)
                guard introSharing.v1.type == .introduction else {
                    print("❌ \u{001B}[1;31m[RECV-SERVER]\u{001B}[0m Frame yang diterima bukan Introduction: \(introSharing.v1.type)")
                    throw ReceiverServerError.unexpectedFrame(expected: .introduction, actual: .introduction)
                }

                var items: [TransferItem] = []
                for meta in introSharing.v1.introduction.fileMetadata {
                    let item = TransferItem(
                        fileName: meta.name.isEmpty ? "file_\(meta.payloadID)" : meta.name,
                        mimeType: meta.mimeType.isEmpty ? "application/octet-stream" : meta.mimeType,
                        fileSize: meta.size,
                        localURL: nil,
                        sha256Checksum: nil
                    )
                    items.append(item)
                }

                let isTextTransfer = items.isEmpty && !introSharing.v1.introduction.textMetadata.isEmpty
                if isTextTransfer {
                    for textMeta in introSharing.v1.introduction.textMetadata {
                        let title = textMeta.textTitle.isEmpty ? "Teks Clipboard" : textMeta.textTitle
                        let item = TransferItem(
                            fileName: title,
                            mimeType: "text/plain",
                            fileSize: textMeta.size,
                            localURL: nil,
                            sha256Checksum: nil
                        )
                        items.append(item)
                    }
                }

                let totalBytes = items.reduce(0) { $0 + $1.fileSize }
                print("📄 \u{001B}[1;34m[RECV-SERVER]\u{001B}[0m [Langkah 7/8] IntroductionFrame diterima: \(items.count) item (\(totalBytes) bytes). Meminta persetujuan pengguna...")

                var session = TransferSession(
                    peerEndpointId: peerEndpointId,
                    direction: .incoming,
                    state: .waitingAcceptance,
                    authPin: pin,
                    totalBytes: totalBytes,
                    items: items
                )

                // 7. Konfirmasi Penerimaan (Acceptance Prompt)
                let isAccepted: Bool
                if let acceptanceHandler = onRequestAcceptance {
                    isAccepted = await acceptanceHandler(session)
                } else {
                    isAccepted = true
                }

                if !isAccepted {
                    print("⛔ \u{001B}[1;33m[RECV-SERVER]\u{001B}[0m Pengguna menolak transfer. Mengirim Consent REJECT...")
                    let (rej1, rej2) = try engine.makeConsentResponseRejectFrames()
                    try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(rej1), on: connection)
                    try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(rej2), on: connection)
                    session.fail(with: "Ditolak oleh pengguna lokal.")
                    connection.cancel()
                    return
                }

                print("✅ \u{001B}[1;32m[RECV-SERVER]\u{001B}[0m Transfer DISETUJUI. Mengirim Consent ACCEPT ke ponsel...")
                // Kirim respon persetujuan (Consent Frame: Data + lastChunk)
                let (acc1, acc2) = try engine.makeConsentResponseAcceptFrames()
                try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(acc1), on: connection)
                try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(acc2), on: connection)

                try session.transition(to: .transferring)
                print("📦 \u{001B}[1;36m[RECV-SERVER]\u{001B}[0m [Langkah 8/8] Memulai penerimaan aliran berkas/teks...")

                // 8. Alirkan Berkas atau Teks Masuk
                if isTextTransfer {
                    var textBuffer = Data()
                    let targetSize = max(1, session.totalBytes)
                    let textPayloadId = introSharing.v1.introduction.textMetadata.first?.payloadID ?? 0
                    while textBuffer.count < targetSize {
                        let chunkSmsg = try await receiveLengthPrefixedData(from: connection)
                        let chunkOffline = try engine.decryptSecureMessage(chunkSmsg)

                        if chunkOffline.v1.type == .disconnection { break }
                        if chunkOffline.v1.type == .keepAlive {
                            let ack = try engine.makeKeepAliveFrame(ack: true)
                            try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(ack), on: connection)
                            continue
                        }
                        guard chunkOffline.v1.type == .payloadTransfer else { continue }

                        let header = chunkOffline.v1.payloadTransfer.payloadHeader
                        let chunk = chunkOffline.v1.payloadTransfer.payloadChunk

                        // Abaikan frame kontrol non-text
                        if textPayloadId != 0 && header.id != textPayloadId && header.type == .bytes {
                            if (chunk.flags & 1) == 1 {
                                if let controlFrame = try? Sharing_Nearby_Frame(serializedData: chunk.body) {
                                    if controlFrame.v1.type == .cancel {
                                        throw ReceiverServerError.transferCancelled
                                    }
                                }
                            }
                            continue
                        }

                        textBuffer.append(chunk.body)
                        session.updateProgress(
                            transferredBytes: Int64(textBuffer.count),
                            speedBytesPerSecond: 0
                        )

                        if (chunk.flags & 1) == 1 || textBuffer.count >= targetSize { break }
                    }

                    if let textString = String(data: textBuffer, encoding: .utf8) {
                        Task { @MainActor in
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(textString, forType: .string)
                        }

                        let senderDisplayName = peerName.isEmpty ? "Samsung Quick Share" : peerName
                        let previewText = textString.count > 100 ? String(textString.prefix(100)) + "..." : textString

                        let content = UNMutableNotificationContent()
                        content.title = "TossShare - Teks Clipboard Diterima"
                        content.body = "\(senderDisplayName): \"\(previewText)\""
                        content.sound = .default

                        let request = UNNotificationRequest(
                            identifier: "clipboard-\(session.sessionId.uuidString)",
                            content: content,
                            trigger: nil
                        )
                        try? await UNUserNotificationCenter.current().add(request)

                        print("📋 \u{001B}[1;32m[RECV-SERVER]\u{001B}[0m Teks clipboard berhasil disalin ke macOS Pasteboard: '\(previewText)'")
                        onClipboardReceived?(textString, senderDisplayName)
                    }
                } else {
                    struct StagedFile {
                        let item: TransferItem
                        let payloadId: Int64
                        let stagingURL: URL
                        let destURL: URL
                        let fileHandle: FileHandle
                        var bytesReceived: Int64
                    }

                    let isBatch = introSharing.v1.introduction.fileMetadata.count > 1 || session.items.count > 1
                    let targetBatchDirectory: URL? = {
                        if isBatch {
                            let batchDir = fileManager.resolveBatchDestinationDirectory(peerName: peerName)
                            try? FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
                            return batchDir
                        }
                        return nil
                    }()
                    session.savedDirectory = targetBatchDirectory
                    if let batchDir = targetBatchDirectory {
                        print("📁 \u{001B}[1;36m[RECV-SERVER]\u{001B}[0m Menyiapkan subfolder batch untuk \(session.items.count) berkas: '\(batchDir.lastPathComponent)'")
                    }

                    var stagedFiles: [Int64: StagedFile] = [:]
                    for meta in introSharing.v1.introduction.fileMetadata {
                        let fileName = meta.name.isEmpty ? "file_\(meta.payloadID)" : meta.name
                        let item = TransferItem(
                            fileName: fileName,
                            mimeType: meta.mimeType.isEmpty ? "application/octet-stream" : meta.mimeType,
                            fileSize: meta.size,
                            localURL: nil,
                            sha256Checksum: nil
                        )
                        let destURL = fileManager.resolveDestinationURL(for: fileName, in: targetBatchDirectory)
                        let stagingURL = fileManager.createStagingURL(for: destURL)
                        activeStagingURL = stagingURL

                        FileManager.default.createFile(atPath: stagingURL.path, contents: nil)
                        let fileHandle = try FileHandle(forWritingTo: stagingURL)
                        stagedFiles[meta.payloadID] = StagedFile(
                            item: item,
                            payloadId: meta.payloadID,
                            stagingURL: stagingURL,
                            destURL: destURL,
                            fileHandle: fileHandle,
                            bytesReceived: 0
                        )
                        print("📥 \u{001B}[1;36m[RECV-SERVER]\u{001B}[0m Menyiapkan berkas: '\(fileName)' (\(meta.size) bytes, id: \(meta.payloadID))...")
                    }

                    // Fallback jika tidak ada payloadID terdaftar di metadata
                    if stagedFiles.isEmpty {
                        for item in session.items {
                            let destURL = fileManager.resolveDestinationURL(for: item.fileName, in: targetBatchDirectory)
                            let stagingURL = fileManager.createStagingURL(for: destURL)
                            activeStagingURL = stagingURL
                            FileManager.default.createFile(atPath: stagingURL.path, contents: nil)
                            let fileHandle = try FileHandle(forWritingTo: stagingURL)
                            stagedFiles[0] = StagedFile(
                                item: item,
                                payloadId: 0,
                                stagingURL: stagingURL,
                                destURL: destURL,
                                fileHandle: fileHandle,
                                bytesReceived: 0
                            )
                        }
                    }

                    while !stagedFiles.isEmpty {
                        let chunkSmsg = try await receiveLengthPrefixedData(from: connection)
                        let chunkOffline = try engine.decryptSecureMessage(chunkSmsg)

                        if chunkOffline.v1.type == .disconnection {
                            print("⚪ \u{001B}[1;37m[RECV-SERVER]\u{001B}[0m Disconnection frame diterima dari pengirim.")
                            break
                        }

                        if chunkOffline.v1.type == .keepAlive {
                            let ack = try engine.makeKeepAliveFrame(ack: true)
                            try await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(ack), on: connection)
                            continue
                        }

                        guard chunkOffline.v1.type == .payloadTransfer else {
                            print("ℹ️ \u{001B}[1;37m[RECV-SERVER]\u{001B}[0m Melewati non-payload frame: \(chunkOffline.v1.type)")
                            continue
                        }

                        let payloadTransfer = chunkOffline.v1.payloadTransfer
                        let header = payloadTransfer.payloadHeader
                        let chunk = payloadTransfer.payloadChunk

                        // Abaikan frame kontrol (.bytes) seperti consent ACK / cancel
                        if header.type == .bytes {
                            if (chunk.flags & 1) == 1 {
                                if let controlFrame = try? Sharing_Nearby_Frame(serializedData: chunk.body) {
                                    if controlFrame.v1.type == .cancel {
                                        print("⚠️ \u{001B}[1;33m[RECV-SERVER]\u{001B}[0m Pengirim membatalkan transfer.")
                                        throw ReceiverServerError.transferCancelled
                                    }
                                }
                            }
                            continue
                        }

                        guard header.type == .file else {
                            continue
                        }

                        let pId = header.id
                        let targetKey = stagedFiles[pId] != nil ? pId : (stagedFiles.count == 1 ? (stagedFiles.keys.first ?? pId) : pId)
                        guard var staged = stagedFiles[targetKey] else {
                            print("⚠️ \u{001B}[1;33m[RECV-SERVER]\u{001B}[0m Payload file ID \(pId) tidak cocok dengan manifest berkas manapun.")
                            continue
                        }

                        let decryptedChunk = chunk.body
                        if !decryptedChunk.isEmpty {
                            try staged.fileHandle.write(contentsOf: decryptedChunk)
                            staged.bytesReceived += Int64(decryptedChunk.count)

                            session.updateProgress(
                                transferredBytes: session.transferredBytes + Int64(decryptedChunk.count),
                                speedBytesPerSecond: 0
                            )
                        }

                        if (chunk.flags & 1) == 1 || staged.bytesReceived >= staged.item.fileSize {
                            print("🏁 \u{001B}[1;32m[RECV-SERVER]\u{001B}[0m Berkas '\(staged.item.fileName)' selesai diterima (\(staged.bytesReceived) bytes, flags: \(chunk.flags))")
                            try staged.fileHandle.close()
                            stagedFiles.removeValue(forKey: targetKey)

                            try fileManager.finalizeStagingFile(
                                stagingURL: staged.stagingURL,
                                destinationURL: staged.destURL,
                                expectedChecksum: staged.item.sha256Checksum
                            )
                            activeStagingURL = nil
                            if let idx = session.items.firstIndex(where: { $0.fileName == staged.item.fileName }) {
                                session.items[idx].localURL = staged.destURL
                            }
                            print("🎉 \u{001B}[1;32m[RECV-SERVER]\u{001B}[0m Berkas tersimpan permanen: \(staged.destURL.path)")
                        } else {
                            stagedFiles[targetKey] = staged
                        }
                    }
                }

                // 9. Kirim DisconnectionFrame ke pengirim dan akhiri sesi secara anggun
                if let disconn = try? engine.makeDisconnectionFrame() {
                    _ = try? await sendData(QuickShareProtocolEngine.encodeLengthPrefixed(disconn), on: connection)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)

                try session.transition(to: .completed)
                print("🏆 \u{001B}[1;32m[RECV-SERVER]\u{001B}[0m Seluruh sesi transfer dari '\(peerName)' berhasil diselesaikan!")
                onTransferCompleted?(session)
                connection.cancel()

            } catch {
                print("❌ \u{001B}[1;31m[RECV-SERVER-ERROR]\u{001B}[0m Transfer gagal! Error: \(error), Deskripsi: \(error.localizedDescription)")
                if let staging = activeStagingURL {
                    fileManager.cleanupStagingFile(at: staging)
                }
                var failedSession = TransferSession(peerEndpointId: "samsung_client", direction: .incoming, state: .failed)
                failedSession.fail(with: error.localizedDescription)
                onTransferFailed?(failedSession, error)
                connection.cancel()
            }
        }
    }

    // MARK: - Low-Level Network Helpers

    private func sendData(_ data: Data, on connection: NWConnection) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let err = error {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveLengthPrefixedData(from connection: NWConnection) async throws -> Data {
        let lengthHeader = try await receiveExactBytes(count: 4, from: connection)
        let payloadLength = (UInt32(lengthHeader[0]) << 24) |
                            (UInt32(lengthHeader[1]) << 16) |
                            (UInt32(lengthHeader[2]) << 8)  |
                            UInt32(lengthHeader[3])

        guard payloadLength < 10 * 1024 * 1024 else {
            throw ReceiverServerError.invalidHandshakePayload
        }
        return try await receiveExactBytes(count: Int(payloadLength), from: connection)
    }

    private func receiveSharingFrame(from connection: NWConnection, using engine: QuickShareProtocolEngine) async throws -> Sharing_Nearby_Frame {
        var buffer = Data()
        while true {
            let rawSmsg = try await receiveLengthPrefixedData(from: connection)
            let offline = try engine.decryptSecureMessage(rawSmsg)

            if offline.v1.type == .disconnection {
                throw ReceiverServerError.connectionClosedPrematurely
            }

            if offline.v1.type == .keepAlive {
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

    private final class AtomicFlag: @unchecked Sendable {
        private var value = false
        private let lock = NSLock()
        func testAndSet() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let old = value
            value = true
            return old
        }
    }

    private func receiveExactBytes(count: Int, from connection: NWConnection) async throws -> Data {
        if count == 0 { return Data() }
        var buffer = Data()
        while buffer.count < count {
            let needed = count - buffer.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                let flag = AtomicFlag()
                connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { content, _, isComplete, error in
                    guard !flag.testAndSet() else { return }
                    if let err = error {
                        continuation.resume(throwing: err)
                    } else if let data = content, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: ReceiverServerError.connectionClosedPrematurely)
                    } else {
                        continuation.resume(throwing: ReceiverServerError.connectionClosedPrematurely)
                    }
                }
            }
            buffer.append(chunk)
        }
        return buffer
    }
}

public enum ReceiverServerError: Error, Equatable, Sendable, LocalizedError {
    case invalidPort(Int)
    case invalidHandshakePayload
    case keyDerivationFailed
    case unexpectedFrame(expected: NearbyFrameType, actual: NearbyFrameType)
    case corruptChunkPacket
    case connectionClosedPrematurely
    case storageFull
    case transferTimedOut
    case transferCancelled

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Nomor port server (\(port)) tidak valid."
        case .invalidHandshakePayload:
            return "Format jabat tangan penerima tidak valid atau sesi terputus."
        case .keyDerivationFailed:
            return "Gagal menurunkan kunci sesi kriptografi UKEY2 penerima."
        case .unexpectedFrame(let exp, let act):
            return "Menerima frame tidak terduga pada server (ekspektasi: \(exp), aktual: \(act))."
        case .corruptChunkPacket:
            return "Paket chunk data yang diterima rusak atau tidak lengkap."
        case .connectionClosedPrematurely:
            return "Koneksi pengirim terputus sebelum transfer tuntas."
        case .storageFull:
            return "Ruang penyimpanan disk Mac penuh. Tidak dapat menerima berkas."
        case .transferTimedOut:
            return "Waktu tunggu sesi penerima kedaluwarsa."
        case .transferCancelled:
            return "Transfer dibatalkan oleh perangkat pengirim."
        }
    }
}
