//
//  EndpointInfoParser.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation

/// Hasil uraian data endpoint info dari TXT Record `n` Quick Share mDNS.
public struct ParsedEndpointInfo: Equatable, Sendable {
    public let friendlyName: String
    public let deviceType: DeviceType
    public let salt: Data
    public let isPrivacyMode: Bool

    public init(friendlyName: String, deviceType: DeviceType, salt: Data, isPrivacyMode: Bool = false) {
        self.friendlyName = friendlyName
        self.deviceType = deviceType
        self.salt = salt
        self.isPrivacyMode = isPrivacyMode
    }
}

/// Pengurai TXT Record `n` mDNS Quick Share / Nearby Share.
public struct EndpointInfoParser: Sendable {

    /// Mengurai string TXT record `n` (format Base64 standard atau URL-safe).
    public static func parse(nRecord: String) throws -> ParsedEndpointInfo {
        // Normalisasi Base64 (mengubah URL-safe '-' dan '_' ke '+' dan '/', serta menambahkan padding '=')
        var base64 = nRecord
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: base64) else {
            throw EndpointInfoParseError.invalidBase64Encoding
        }

        return try parse(data: data)
    }

    /// Mengurai data biner endpoint info mentah.
    public static func parse(data: Data) throws -> ParsedEndpointInfo {
        // Standar Google/Samsung Quick Share: payload privasi minimal 17 bytes (1B type/visibility + 16B salt)
        guard data.count >= 17 else {
            throw EndpointInfoParseError.payloadTooShort(data.count)
        }

        // Byte 0: Bitfield tipe perangkat
        let byte0 = data[0]
        let rawType = (byte0 >> 1) & 0x07
        let deviceType: DeviceType
        switch rawType {
        case 1, 5: // 1 = phone, 5 = foldable
            deviceType = .phone
        case 2:
            deviceType = .tablet
        case 3:
            deviceType = .laptop
        default:
            // Fallback jika bitfield direct
            if (byte0 & 0x07) == 1 { deviceType = .phone }
            else if (byte0 & 0x07) == 2 { deviceType = .tablet }
            else if (byte0 & 0x07) == 3 { deviceType = .laptop }
            else { deviceType = .unknown }
        }

        // Byte 1..16: Salt (16 Bytes)
        let salt = data.subdata(in: 1..<17)

        var friendlyName: String
        let defaultGalaxyName: String = {
            switch deviceType {
            case .phone: return rawType == 5 ? "Samsung Galaxy Fold" : "Samsung Galaxy Phone"
            case .tablet: return "Samsung Galaxy Tab"
            case .laptop: return "Samsung Galaxy Book"
            case .unknown: return "Samsung Device"
            }
        }()

        let isPrivacyMode = (data.count <= 17)

        if isPrivacyMode {
            // Samsung Quick Share dalam mode privasi (Hanya Kontak) tidak menyertakan plaintext nama di mDNS
            friendlyName = defaultGalaxyName
        } else {
            // Byte 17: Panjang string nama perangkat
            let nameLength = Int(data[17])
            let expectedEnd = 18 + nameLength

            if nameLength > 0 && expectedEnd <= data.count {
                let nameData = data.subdata(in: 18..<expectedEnd)
                friendlyName = String(data: nameData, encoding: .utf8) ?? defaultGalaxyName
            } else if data.count > 18 {
                let nameData = data.subdata(in: 18..<data.count)
                friendlyName = String(data: nameData, encoding: .utf8) ?? defaultGalaxyName
            } else {
                friendlyName = defaultGalaxyName
            }
        }

        if friendlyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            friendlyName = defaultGalaxyName
        }

        return ParsedEndpointInfo(
            friendlyName: friendlyName,
            deviceType: deviceType,
            salt: salt,
            isPrivacyMode: isPrivacyMode
        )
    }

    /// Membuat data TXT record `n` biner dan string base64 untuk keperluan testing atau broadcasting.
    public static func createRecord(friendlyName: String, deviceType: DeviceType, salt: Data? = nil) -> String {
        var data = Data()

        // Byte 0
        let typeCode: UInt8
        switch deviceType {
        case .phone: typeCode = 1
        case .tablet: typeCode = 2
        case .laptop: typeCode = 3
        case .unknown: typeCode = 0
        }
        data.append((typeCode << 1) | 0x00) // bitfield

        // Salt 16 bytes
        let saltBytes = salt ?? CryptoEngine.secureRandomBytes(count: 16)
        if saltBytes.count == 16 {
            data.append(saltBytes)
        } else {
            data.append(saltBytes.prefix(16))
        }

        // Name length & string
        let nameData = friendlyName.data(using: .utf8) ?? Data()
        data.append(UInt8(min(255, nameData.count)))
        data.append(nameData)

        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// Membangkitkan nama layanan instans mDNS berukuran tepat 10-byte yang di-encode ke Base64 URL-safe (standar resmi Quick Share).
    /// Format: [0x23 (PCP byte)] + [4-byte endpointId] + [0xFC, 0x9F, 0x5E (Service ID Hash)] + [0x00, 0x00 (Reserved)]
    public static func generateMdnsInstanceName(endpointId: String) -> String {
        var data = Data()
        data.append(0x23)
        let epBytes = Array(endpointId.utf8.prefix(4))
        if epBytes.count == 4 {
            data.append(contentsOf: epBytes)
        } else {
            var padded = epBytes
            while padded.count < 4 {
                padded.append(0x30) // '0'
            }
            data.append(contentsOf: padded)
        }
        data.append(contentsOf: [0xFC, 0x9F, 0x5E])
        data.append(contentsOf: [0x00, 0x00])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// Mengekstrak 4-karakter endpointId asli dari nama instans mDNS 10-byte Quick Share (Base64 URL-safe).
    /// Format: [0x23 (PCP byte)] + [4-byte endpointId] + [0xFC, 0x9F, 0x5E] + [0x00, 0x00]
    public static func extractEndpointId(fromMdnsInstanceName name: String) -> String? {
        var base64 = name
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = base64.count % 4
        if rem > 0 { base64.append(String(repeating: "=", count: 4 - rem)) }
        guard let data = Data(base64Encoded: base64), data.count >= 5, data[0] == 0x23 else {
            return nil
        }
        let idData = data.subdata(in: 1..<5)
        return String(data: idData, encoding: .utf8)
    }
}

public enum EndpointInfoParseError: Error, Equatable, Sendable {
    case invalidBase64Encoding
    case payloadTooShort(Int)
}
