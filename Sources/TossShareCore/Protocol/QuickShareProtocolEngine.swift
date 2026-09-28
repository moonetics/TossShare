//
//  QuickShareProtocolEngine.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import Network
import CryptoKit
import CommonCrypto
import SwiftProtobuf

/// Helper kriptografi dan framing protokol resmi Google Quick Share / Nearby Connections.
final class QuickShareProtocolEngine: @unchecked Sendable {

    internal let privateKey: P256.KeyAgreement.PrivateKey
    internal let localPublicKeyData: Data // 65-byte uncompressed X9.63 (0x04 + X + Y)
    internal let localX: Data // 32 bytes
    internal let localY: Data // 32 bytes

    // UKEY2 Raw Messages for Salt/Info binding
    internal private(set) var ukeyClientInitData: Data?
    internal private(set) var ukeyServerInitData: Data?
    internal private(set) var ukeyClientFinishData: Data?
    internal private(set) var expectedClientFinishCommitment: Data?

    // Derived Credentials
    internal private(set) var authPin: String?
    internal private(set) var authKey: SymmetricKey?

    internal enum Role: Sendable {
        case sender
        case receiver
    }

    internal let role: Role

    // SecureMessage Keys
    private var encryptKey: [UInt8]?
    private var decryptKey: [UInt8]?
    private var sendHmacKey: SymmetricKey?
    private var recvHmacKey: SymmetricKey?

    // Monotonic sequence numbers for SecureMessage envelopes
    private var sendSeq: Int32 = 0
    private var recvSeq: Int32 = 0

    internal init(role: Role = .sender) {
        self.role = role
        let key = P256.KeyAgreement.PrivateKey()
        self.privateKey = key
        let x963 = key.publicKey.x963Representation
        self.localPublicKeyData = x963
        self.localX = x963.subdata(in: 1..<33)
        self.localY = x963.subdata(in: 33..<65)
    }

    // MARK: - Two's Complement Integer Helpers (Google / Java BigInteger standard)

    /// Meng-encode nilai magnitude big-endian menjadi integer two's complement bertanda (signed) big-endian.
    /// Standar Google UKEY2 / Protobuf SecureMessage: koordinat X dan Y adalah two's-complement integer.
    /// Jika bit paling signifikan (MSB) bernilai 1 (byte[0] >= 0x80), byte 0x00 wajib disisipkan di depan agar tidak terbaca negatif oleh Java BigInteger Android.
    internal static func encodeBigEndianTwosComplement(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        while bytes.count > 1 && bytes[0] == 0 {
            bytes.removeFirst()
        }
        if let first = bytes.first, (first & 0x80) != 0 {
            bytes.insert(0x00, at: 0)
        }
        return Data(bytes)
    }

    /// Men-decode integer two's complement big-endian dari peer (Android Samsung) menjadi tepat 32-byte magnitude untuk kurva P-256.
    /// Menghilangkan byte 0x00 tanda positif jika ukuran > 32 bytes, dan melakukan left-padding jika ukuran < 32 bytes.
    internal static func decodeBigEndianTwosComplementTo32Bytes(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        while bytes.count > 32 && bytes.first == 0 {
            bytes.removeFirst()
        }
        if bytes.count < 32 {
            let padding = [UInt8](repeating: 0, count: 32 - bytes.count)
            bytes = padding + bytes
        }
        return Data(bytes.suffix(32))
    }

    // MARK: - Framing Helpers

    internal static func encodeLengthPrefixed(_ data: Data) -> Data {
        var result = Data(capacity: data.count + 4)
        let length = UInt32(data.count)
        result.append(UInt8((length >> 24) & 0xFF))
        result.append(UInt8((length >> 16) & 0xFF))
        result.append(UInt8((length >> 8) & 0xFF))
        result.append(UInt8(length & 0xFF))
        result.append(data)
        return result
    }

    // MARK: - Connection Request Frame

    internal static func makeConnectionRequestFrame(endpointId: String, endpointName: String) throws -> Data {
        var frame = Location_Nearby_Connections_OfflineFrame()
        frame.version = .v1
        var v1 = Location_Nearby_Connections_V1Frame()
        v1.type = .connectionRequest
        var req = Location_Nearby_Connections_ConnectionRequestFrame()
        req.endpointID = endpointId
        req.endpointName = endpointName
        req.endpointInfo = makeEndpointInfoData(name: endpointName, deviceType: .laptop)
        req.mediums = [.wifiLan]
        req.keepAliveIntervalMillis = 5000
        req.keepAliveTimeoutMillis = 30000
        v1.connectionRequest = req
        frame.v1 = v1
        return try frame.serializedData()
    }

    private static func makeEndpointInfoData(name: String, deviceType: DeviceType) -> Data {
        var data = Data()
        let typeCode: UInt8
        switch deviceType {
        case .phone: typeCode = 1
        case .tablet: typeCode = 2
        case .laptop: typeCode = 3
        case .unknown: typeCode = 0
        }
        data.append((typeCode << 1) | 0x00) // bitfield
        data.append(CryptoEngine.secureRandomBytes(count: 16)) // salt 16 bytes
        let nameBytes = name.data(using: .utf8) ?? Data()
        data.append(UInt8(min(255, nameBytes.count)))
        data.append(nameBytes)
        return data
    }

    // MARK: - UKEY2 Handshake Generation

    internal func makeUkey2ClientInitFrame() throws -> Data {
        // 1. Buat Ukey2ClientFinished terlebih dahulu sebagai komitmen
        var pkey = Securemessage_GenericPublicKey()
        pkey.type = .ecP256
        var ecKey = Securemessage_EcP256PublicKey()
        ecKey.x = Self.encodeBigEndianTwosComplement(localX)
        ecKey.y = Self.encodeBigEndianTwosComplement(localY)
        pkey.ecP256PublicKey = ecKey

        var finish = Securegcm_Ukey2ClientFinished()
        finish.publicKey = try pkey.serializedData()

        var finishFrame = Securegcm_Ukey2Message()
        finishFrame.messageType = .clientFinish
        finishFrame.messageData = try finish.serializedData()
        let finishMsgData = try finishFrame.serializedData()
        self.ukeyClientFinishData = finishMsgData

        // 2. Hash komitmen finish frame dengan SHA-512
        let commitmentHash = Data(SHA512.hash(data: finishMsgData))

        // 3. Buat Ukey2ClientInit
        var clientInit = Securegcm_Ukey2ClientInit()
        clientInit.version = 1
        clientInit.random = CryptoEngine.secureRandomBytes(count: 32)
        clientInit.nextProtocol = "AES_256_CBC-HMAC_SHA256"

        var commitment = Securegcm_Ukey2ClientInit.CipherCommitment()
        commitment.commitment = commitmentHash
        commitment.handshakeCipher = .p256Sha512
        clientInit.cipherCommitments.append(commitment)

        var initFrame = Securegcm_Ukey2Message()
        initFrame.messageType = .clientInit
        initFrame.messageData = try clientInit.serializedData()

        let initMsgData = try initFrame.serializedData()
        self.ukeyClientInitData = initMsgData
        return initMsgData
    }

    internal func processUkey2ClientInit(clientInitRawData: Data) throws -> Data {
        self.ukeyClientInitData = clientInitRawData
        let ukeyMsg = try Securegcm_Ukey2Message(serializedData: clientInitRawData)
        guard ukeyMsg.messageType == .clientInit else {
            throw QuickShareProtocolError.invalidMessageType
        }

        let clientInit = try Securegcm_Ukey2ClientInit(serializedData: ukeyMsg.messageData)
        guard clientInit.version == 1,
              let p256Commitment = clientInit.cipherCommitments.first(where: { $0.handshakeCipher == .p256Sha512 }) else {
            throw QuickShareProtocolError.handshakeParametersMismatch
        }
        self.expectedClientFinishCommitment = p256Commitment.commitment

        var pkey = Securemessage_GenericPublicKey()
        pkey.type = .ecP256
        var ecKey = Securemessage_EcP256PublicKey()
        ecKey.x = Self.encodeBigEndianTwosComplement(localX)
        ecKey.y = Self.encodeBigEndianTwosComplement(localY)
        pkey.ecP256PublicKey = ecKey

        var serverInit = Securegcm_Ukey2ServerInit()
        serverInit.version = 1
        serverInit.random = CryptoEngine.secureRandomBytes(count: 32)
        serverInit.handshakeCipher = .p256Sha512
        serverInit.publicKey = try pkey.serializedData()

        var serverInitMsg = Securegcm_Ukey2Message()
        serverInitMsg.messageType = .serverInit
        serverInitMsg.messageData = try serverInit.serializedData()

        let servData = try serverInitMsg.serializedData()
        self.ukeyServerInitData = servData
        return servData
    }

    internal func processUkey2ClientFinish(clientFinishRawData: Data) throws {
        self.ukeyClientFinishData = clientFinishRawData
        let ukeyMsg = try Securegcm_Ukey2Message(serializedData: clientFinishRawData)

        if ukeyMsg.messageType == .alert {
            if let alert = try? Securegcm_Ukey2Alert(serializedData: ukeyMsg.messageData) {
                print("🚨 \u{001B}[1;31m[UKEY2-ALERT]\u{001B}[0m Peer mengirim Alert: type=\(alert.type), error=\(alert.errorMessage)")
            }
            throw QuickShareProtocolError.ukey2AlertReceived
        }

        guard ukeyMsg.messageType == .clientFinish else {
            throw QuickShareProtocolError.invalidMessageType
        }

        if let expected = expectedClientFinishCommitment {
            let actualHash = Data(SHA512.hash(data: clientFinishRawData))
            guard actualHash == expected else {
                throw QuickShareProtocolError.commitmentMismatch
            }
        }

        let finish = try Securegcm_Ukey2ClientFinished(serializedData: ukeyMsg.messageData)
        let clientPubKeyProto = try Securemessage_GenericPublicKey(serializedData: finish.publicKey)
        guard clientPubKeyProto.hasEcP256PublicKey else {
            throw QuickShareProtocolError.missingPublicKey
        }

        let peerX = Self.decodeBigEndianTwosComplementTo32Bytes(clientPubKeyProto.ecP256PublicKey.x)
        let peerY = Self.decodeBigEndianTwosComplementTo32Bytes(clientPubKeyProto.ecP256PublicKey.y)

        var rawPoint = Data([0x04])
        rawPoint.append(peerX)
        rawPoint.append(peerY)

        let peerPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: rawPoint)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)

        guard let initData = ukeyClientInitData, let servData = ukeyServerInitData else {
            throw QuickShareProtocolError.missingHandshakeContext
        }

        deriveSessionKeys(sharedSecret: sharedSecret, initData: initData, servData: servData, isServer: true)
    }

    internal func processUkey2ServerInit(serverInitRawData: Data) throws {
        self.ukeyServerInitData = serverInitRawData
        let ukeyMsg = try Securegcm_Ukey2Message(serializedData: serverInitRawData)

        if ukeyMsg.messageType == .alert {
            if let alert = try? Securegcm_Ukey2Alert(serializedData: ukeyMsg.messageData) {
                print("🚨 \u{001B}[1;31m[UKEY2-ALERT]\u{001B}[0m Server target mengirim Alert: type=\(alert.type), error=\(alert.errorMessage)")
            }
            throw QuickShareProtocolError.ukey2AlertReceived
        }

        guard ukeyMsg.messageType == .serverInit else {
            throw QuickShareProtocolError.invalidMessageType
        }

        let serverInit = try Securegcm_Ukey2ServerInit(serializedData: ukeyMsg.messageData)
        guard serverInit.version == 1, serverInit.random.count == 32, serverInit.handshakeCipher == .p256Sha512 else {
            throw QuickShareProtocolError.handshakeParametersMismatch
        }

        let serverPubKeyProto = try Securemessage_GenericPublicKey(serializedData: serverInit.publicKey)
        guard serverPubKeyProto.hasEcP256PublicKey else {
            throw QuickShareProtocolError.missingPublicKey
        }

        let peerX = Self.decodeBigEndianTwosComplementTo32Bytes(serverPubKeyProto.ecP256PublicKey.x)
        let peerY = Self.decodeBigEndianTwosComplementTo32Bytes(serverPubKeyProto.ecP256PublicKey.y)

        var rawPoint = Data([0x04])
        rawPoint.append(peerX)
        rawPoint.append(peerY)

        let peerPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: rawPoint)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)

        guard let initData = ukeyClientInitData, let servData = ukeyServerInitData else {
            throw QuickShareProtocolError.missingHandshakeContext
        }

        deriveSessionKeys(sharedSecret: sharedSecret, initData: initData, servData: servData, isServer: false)
    }

    private func deriveSessionKeys(sharedSecret: SharedSecret, initData: Data, servData: Data, isServer: Bool) {
        let dhs = sharedSecret.withUnsafeBytes { ptr in
            Data(SHA256.hash(data: Data(ptr)))
        }

        var ukeyInfo = Data()
        ukeyInfo.append(initData)
        ukeyInfo.append(servData)

        let authKeySym = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: dhs),
            salt: "UKEY2 v1 auth".data(using: .utf8)!,
            info: ukeyInfo,
            outputByteCount: 32
        )
        self.authKey = authKeySym
        self.authPin = Self.pinCodeFromAuthKey(authKeySym)

        let nextSecret = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: dhs),
            salt: "UKEY2 v1 next".data(using: .utf8)!,
            info: ukeyInfo,
            outputByteCount: 32
        )

        let d2dSalt = Data([
            0x82, 0xAA, 0x55, 0xA0, 0xD3, 0x97, 0xF8, 0x83, 0x46, 0xCA, 0x1C,
            0xEE, 0x8D, 0x39, 0x09, 0xB9, 0x5F, 0x13, 0xFA, 0x7D, 0xEB, 0x1D,
            0x4A, 0xB3, 0x83, 0x76, 0xB8, 0x25, 0x6D, 0xA8, 0x55, 0x10
        ])

        let d2dClientKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: nextSecret,
            salt: d2dSalt,
            info: "client".data(using: .utf8)!,
            outputByteCount: 32
        )
        let d2dServerKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: nextSecret,
            salt: d2dSalt,
            info: "server".data(using: .utf8)!,
            outputByteCount: 32
        )

        let smsgSalt = Data(SHA256.hash(data: "SecureMessage".data(using: .utf8)!))

        let clientKeyBytes = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: d2dClientKey,
            salt: smsgSalt,
            info: "ENC:2".data(using: .utf8)!,
            outputByteCount: 32
        ).withUnsafeBytes { [UInt8]($0) }
        let clientHmacKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: d2dClientKey,
            salt: smsgSalt,
            info: "SIG:1".data(using: .utf8)!,
            outputByteCount: 32
        )

        let serverKeyBytes = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: d2dServerKey,
            salt: smsgSalt,
            info: "ENC:2".data(using: .utf8)!,
            outputByteCount: 32
        ).withUnsafeBytes { [UInt8]($0) }
        let serverHmacKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: d2dServerKey,
            salt: smsgSalt,
            info: "SIG:1".data(using: .utf8)!,
            outputByteCount: 32
        )

        if isServer {
            self.encryptKey = serverKeyBytes
            self.sendHmacKey = serverHmacKey
            self.decryptKey = clientKeyBytes
            self.recvHmacKey = clientHmacKey
        } else {
            self.encryptKey = clientKeyBytes
            self.sendHmacKey = clientHmacKey
            self.decryptKey = serverKeyBytes
            self.recvHmacKey = serverHmacKey
        }
    }

    internal static func pinCodeFromAuthKey(_ key: SymmetricKey) -> String {
        var hash: Int = 0
        var multiplier: Int = 1
        let keyBytes = key.withUnsafeBytes { [UInt8]($0) }

        for _byte in keyBytes {
            let byte = Int(Int8(bitPattern: _byte))
            hash = (hash + byte * multiplier) % 9973
            multiplier = (multiplier * 31) % 9973
        }

        return String(format: "%04d", abs(hash))
    }

    // MARK: - Connection Response Frame

    internal static func makeConnectionResponseAcceptFrame() throws -> Data {
        var resp = Location_Nearby_Connections_OfflineFrame()
        resp.version = .v1
        var v1 = Location_Nearby_Connections_V1Frame()
        v1.type = .connectionResponse
        var connResp = Location_Nearby_Connections_ConnectionResponseFrame()
        connResp.response = .accept
        connResp.status = 0
        var osInfo = Location_Nearby_Connections_OsInfo()
        osInfo.type = .apple
        connResp.osInfo = osInfo
        v1.connectionResponse = connResp
        resp.v1 = v1
        return try resp.serializedData()
    }

    // MARK: - SecureChannel Encryption & Decryption (AES-256-CBC + HMAC-SHA256)

    internal func encryptOfflineFrame(_ frame: Location_Nearby_Connections_OfflineFrame) throws -> Data {
        guard let encKey = encryptKey, let hmacKey = sendHmacKey else {
            throw QuickShareProtocolError.encryptionNotInitialized
        }

        sendSeq += 1
        var d2dMsg = Securegcm_DeviceToDeviceMessage()
        d2dMsg.message = try frame.serializedData()
        d2dMsg.sequenceNumber = sendSeq

        let plainData = try d2dMsg.serializedData()
        let iv = CryptoEngine.secureRandomBytes(count: 16)

        var encryptedData = Data(count: plainData.count + 16)
        var encryptedLength: size_t = 0

        let status = encryptedData.withUnsafeMutableBytes { outBuf in
            plainData.withUnsafeBytes { inBuf in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES128),
                    CCOptions(kCCOptionPKCS7Padding),
                    encKey, kCCKeySizeAES256,
                    [UInt8](iv),
                    inBuf.baseAddress, inBuf.count,
                    outBuf.baseAddress, outBuf.count,
                    &encryptedLength
                )
            }
        }
        guard status == kCCSuccess else {
            throw QuickShareProtocolError.cryptError(status)
        }

        var hb = Securemessage_HeaderAndBody()
        hb.body = encryptedData.prefix(encryptedLength)
        var hdr = Securemessage_Header()
        hdr.encryptionScheme = .aes256Cbc
        hdr.signatureScheme = .hmacSha256
        hdr.iv = iv

        var md = Securegcm_GcmMetadata()
        md.type = .deviceToDeviceMessage
        md.version = 1
        hdr.publicMetadata = try md.serializedData()
        hb.header = hdr

        var smsg = Securemessage_SecureMessage()
        let hbData = try hb.serializedData()
        smsg.headerAndBody = hbData
        smsg.signature = Data(HMAC<SHA256>.authenticationCode(for: hbData, using: hmacKey))

        return try smsg.serializedData()
    }

    internal func decryptSecureMessage(_ smsgData: Data) throws -> Location_Nearby_Connections_OfflineFrame {
        guard let decKey = decryptKey, let hmacKey = recvHmacKey else {
            throw QuickShareProtocolError.encryptionNotInitialized
        }

        let smsg = try Securemessage_SecureMessage(serializedData: smsgData)
        guard smsg.hasSignature, smsg.hasHeaderAndBody else {
            throw QuickShareProtocolError.missingSecureMessageFields
        }

        let expectedHmac = Data(HMAC<SHA256>.authenticationCode(for: smsg.headerAndBody, using: hmacKey))
        guard expectedHmac == smsg.signature else {
            throw QuickShareProtocolError.hmacMismatch
        }

        let headerAndBody = try Securemessage_HeaderAndBody(serializedData: smsg.headerAndBody)
        let cipherBody = headerAndBody.body
        let iv = [UInt8](headerAndBody.header.iv)

        var decryptedData = Data(count: cipherBody.count)
        var decryptedLength: size_t = 0

        let status = decryptedData.withUnsafeMutableBytes { outBuf in
            cipherBody.withUnsafeBytes { inBuf in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES128),
                    CCOptions(kCCOptionPKCS7Padding),
                    decKey, kCCKeySizeAES256,
                    iv,
                    inBuf.baseAddress, inBuf.count,
                    outBuf.baseAddress, outBuf.count,
                    &decryptedLength
                )
            }
        }
        guard status == kCCSuccess else {
            throw QuickShareProtocolError.cryptError(status)
        }

        let plainD2D = decryptedData.prefix(decryptedLength)
        let d2dMsg = try Securegcm_DeviceToDeviceMessage(serializedData: plainD2D)
        recvSeq += 1

        return try Location_Nearby_Connections_OfflineFrame(serializedData: d2dMsg.message)
    }

    // MARK: - Consent Response Frame (Receiver -> Sender)

    internal func makeConsentResponseAcceptFrames() throws -> (Data, Data) {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        var v1 = Sharing_Nearby_V1Frame()
        v1.type = .response
        var resp = Sharing_Nearby_ConnectionResponseFrame()
        resp.status = .accept
        v1.connectionResponse = resp
        frame.v1 = v1
        return try makeTransferSetupBytesFrames(frame: frame)
    }

    internal func makeConsentResponseRejectFrames() throws -> (Data, Data) {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        var v1 = Sharing_Nearby_V1Frame()
        v1.type = .response
        var resp = Sharing_Nearby_ConnectionResponseFrame()
        resp.status = .reject
        v1.connectionResponse = resp
        frame.v1 = v1
        return try makeTransferSetupBytesFrames(frame: frame)
    }

    internal func makeConsentResponseAcceptFrame() throws -> Data {
        let (data, _) = try makeConsentResponseAcceptFrames()
        return data
    }

    internal func makeConsentResponseRejectFrame() throws -> Data {
        let (data, _) = try makeConsentResponseRejectFrames()
        return data
    }

    // MARK: - Transfer Setup Frames (Wrapped in Bytes Payload + LastChunk EOF)

    /// Membungkus frame protokol ke dalam pasangan PayloadTransferFrame: Frame Data (flags=0) dan Frame EOF (flags=1) dengan payloadId identik.
    internal func makeTransferSetupBytesFrames(frame: Sharing_Nearby_Frame) throws -> (Data, Data) {
        let payloadData = try frame.serializedData()
        let payloadId = Int64.random(in: 100_000...Int64.max)
        let totalSize = Int64(payloadData.count)

        // 1. Frame Data
        var transfer = Location_Nearby_Connections_PayloadTransferFrame()
        transfer.packetType = .data
        transfer.payloadChunk.offset = 0
        transfer.payloadChunk.flags = 0
        transfer.payloadChunk.body = payloadData
        transfer.payloadHeader.id = payloadId
        transfer.payloadHeader.type = .bytes
        transfer.payloadHeader.totalSize = totalSize
        transfer.payloadHeader.isSensitive = false

        var wrapper1 = Location_Nearby_Connections_OfflineFrame()
        wrapper1.version = .v1
        var v1_1 = Location_Nearby_Connections_V1Frame()
        v1_1.type = .payloadTransfer
        v1_1.payloadTransfer = transfer
        wrapper1.v1 = v1_1
        let encrypted1 = try encryptOfflineFrame(wrapper1)

        // 2. Frame Penutup (EOF lastChunk)
        var lastTransfer = Location_Nearby_Connections_PayloadTransferFrame()
        lastTransfer.packetType = .data
        lastTransfer.payloadChunk.offset = totalSize
        lastTransfer.payloadChunk.flags = 1 // .lastChunk
        lastTransfer.payloadChunk.body = Data()
        lastTransfer.payloadHeader.id = payloadId
        lastTransfer.payloadHeader.type = .bytes
        lastTransfer.payloadHeader.totalSize = totalSize
        lastTransfer.payloadHeader.isSensitive = false

        var wrapper2 = Location_Nearby_Connections_OfflineFrame()
        wrapper2.version = .v1
        var v1_2 = Location_Nearby_Connections_V1Frame()
        v1_2.type = .payloadTransfer
        v1_2.payloadTransfer = lastTransfer
        wrapper2.v1 = v1_2
        let encrypted2 = try encryptOfflineFrame(wrapper2)

        return (encrypted1, encrypted2)
    }

    internal func makeTransferSetupBytesPayload(frame: Sharing_Nearby_Frame) throws -> Data {
        let (data, _) = try makeTransferSetupBytesFrames(frame: frame)
        return data
    }

    // MARK: - Paired Key Encryption Frame

    internal static func makePairedKeyEncryptionFrame() -> Sharing_Nearby_Frame {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        var v1 = Sharing_Nearby_V1Frame()
        v1.type = .pairedKeyEncryption
        var paired = Sharing_Nearby_PairedKeyEncryptionFrame()
        paired.secretIDHash = CryptoEngine.secureRandomBytes(count: 6)
        paired.signedData = CryptoEngine.secureRandomBytes(count: 72)
        v1.pairedKeyEncryption = paired
        frame.v1 = v1
        return frame
    }

    // MARK: - Paired Key Result Frame

    internal static func makePairedKeyResultFrame() -> Sharing_Nearby_Frame {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        var v1 = Sharing_Nearby_V1Frame()
        v1.type = .pairedKeyResult
        var res = Sharing_Nearby_PairedKeyResultFrame()
        res.status = .unable
        v1.pairedKeyResult = res
        frame.v1 = v1
        return frame
    }

    // MARK: - Introduction Frame (Carrying File Metadata)

    internal static func makeIntroductionFrame(items: [TransferItem]) -> (Sharing_Nearby_Frame, [Int64]) {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        var v1 = Sharing_Nearby_V1Frame()
        v1.type = .introduction

        var intro = Sharing_Nearby_IntroductionFrame()
        var payloadIds: [Int64] = []

        for item in items {
            var meta = Sharing_Nearby_FileMetadata()
            meta.name = item.fileName
            meta.size = item.fileSize

            let ext = (item.fileName as NSString).pathExtension.lowercased()
            switch ext {
            case "jpg", "jpeg", "png", "heic", "webp", "gif":
                meta.type = .image
                meta.mimeType = "image/\(ext)"
            case "mp4", "mov", "mkv", "webm":
                meta.type = .video
                meta.mimeType = "video/\(ext)"
            case "mp3", "m4a", "wav", "flac":
                meta.type = .audio
                meta.mimeType = "audio/\(ext)"
            case "pdf", "docx", "doc", "txt", "xlsx", "zip":
                meta.type = .document
                meta.mimeType = "application/octet-stream"
            case "apk":
                meta.type = .androidApp
                meta.mimeType = "application/vnd.android.package-archive"
            default:
                meta.type = .unknown
                meta.mimeType = "application/octet-stream"
            }

            let pId = Int64.random(in: 1_000_000...Int64.max)
            meta.payloadID = pId
            payloadIds.append(pId)
            intro.fileMetadata.append(meta)
        }

        v1.introduction = intro
        frame.v1 = v1
        return (frame, payloadIds)
    }

    // MARK: - Text Introduction Frame (Clipboard Sync)

    internal static func makeTextIntroductionFrame(text: String, title: String = "Teks Clipboard") -> (Sharing_Nearby_Frame, Int64) {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        var v1 = Sharing_Nearby_V1Frame()
        v1.type = .introduction

        var intro = Sharing_Nearby_IntroductionFrame()
        var textMeta = Sharing_Nearby_TextMetadata()
        textMeta.textTitle = title
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            textMeta.type = .url
        } else {
            textMeta.type = .text
        }
        let textSize = Int64(text.utf8.count)
        textMeta.size = textSize
        let payloadId = Int64.random(in: 1_000_000...Int64.max)
        textMeta.payloadID = payloadId

        intro.textMetadata.append(textMeta)
        v1.introduction = intro
        frame.v1 = v1
        return (frame, payloadId)
    }

    // MARK: - File Chunks & Disconnection

    internal func makeFileChunkFrame(
        payloadId: Int64,
        totalSize: Int64,
        offset: Int64,
        chunkData: Data,
        isLast: Bool,
        fileName: String? = nil
    ) throws -> Data {
        var transfer = Location_Nearby_Connections_PayloadTransferFrame()
        transfer.packetType = .data
        transfer.payloadChunk.offset = offset
        transfer.payloadChunk.flags = isLast ? 1 : 0
        transfer.payloadChunk.body = chunkData
        transfer.payloadHeader.id = payloadId
        transfer.payloadHeader.type = .file
        transfer.payloadHeader.totalSize = totalSize
        transfer.payloadHeader.isSensitive = false
        if let fileName = fileName {
            transfer.payloadHeader.fileName = fileName
        }

        var wrapper = Location_Nearby_Connections_OfflineFrame()
        wrapper.version = .v1
        var v1 = Location_Nearby_Connections_V1Frame()
        v1.type = .payloadTransfer
        v1.payloadTransfer = transfer
        wrapper.v1 = v1

        return try encryptOfflineFrame(wrapper)
    }

    // MARK: - Keep-Alive Frame

    internal func makeKeepAliveFrame(ack: Bool = false) throws -> Data {
        var offlineFrame = Location_Nearby_Connections_OfflineFrame()
        offlineFrame.version = .v1
        var v1 = Location_Nearby_Connections_V1Frame()
        v1.type = .keepAlive
        var keepAlive = Location_Nearby_Connections_KeepAliveFrame()
        keepAlive.ack = ack
        v1.keepAlive = keepAlive
        offlineFrame.v1 = v1
        return try encryptOfflineFrame(offlineFrame)
    }

    internal func makeDisconnectionFrame() throws -> Data {
        var offlineFrame = Location_Nearby_Connections_OfflineFrame()
        offlineFrame.version = .v1
        var v1 = Location_Nearby_Connections_V1Frame()
        v1.type = .disconnection
        v1.disconnection = Location_Nearby_Connections_DisconnectionFrame()
        offlineFrame.v1 = v1
        return try encryptOfflineFrame(offlineFrame)
    }
}

internal enum QuickShareProtocolError: Error, Equatable, Sendable, LocalizedError {
    case invalidMessageType
    case handshakeParametersMismatch
    case missingPublicKey
    case missingHandshakeContext
    case encryptionNotInitialized
    case missingSecureMessageFields
    case hmacMismatch
    case cryptError(Int32)
    case connectionTimeout
    case ukey2AlertReceived
    case commitmentMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidMessageType:
            return "Tipe pesan UKEY2 tidak sesuai dengan urutan jabat tangan yang diharapkan."
        case .handshakeParametersMismatch:
            return "Parameter jabat tangan kriptografi tidak cocok dengan cipher P256-SHA512."
        case .missingPublicKey:
            return "Kunci publik P-256 tidak ditemukan dalam frame jabat tangan."
        case .missingHandshakeContext:
            return "Konteks data handshake UKEY2 tidak lengkap untuk penurunan kunci sesi."
        case .encryptionNotInitialized:
            return "Kanal enkripsi SecureMessage belum diinisialisasi."
        case .missingSecureMessageFields:
            return "Kolom esensial pada pesan SecureMessage tidak lengkap."
        case .hmacMismatch:
            return "Verifikasi integritas HMAC-SHA256 gagal."
        case .cryptError(let code):
            return "Kesalahan CommonCrypto AES-CBC: \(code)."
        case .connectionTimeout:
            return "Batas waktu koneksi protokol terlampaui."
        case .ukey2AlertReceived:
            return "Perangkat target menolak jabat tangan UKEY2 (Alert diterima)."
        case .commitmentMismatch:
            return "Komitmen hash SHA-512 pada ClientFinish tidak cocok dengan ClientInit."
        }
    }
}
