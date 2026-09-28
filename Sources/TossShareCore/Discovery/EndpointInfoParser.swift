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

    public init(friendlyName: String, deviceType: DeviceType, salt: Data) {
        self.friendlyName = friendlyName
        self.deviceType = deviceType
        self.salt = salt
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
        guard data.count >= 18 else {
            throw EndpointInfoParseError.payloadTooShort(data.count)
        }

        // Byte 0: Bitfield tipe perangkat
        let byte0 = data[0]
        let rawType = (byte0 >> 1) & 0x07
        let deviceType: DeviceType
        switch rawType {
        case 1:
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

        // Byte 17: Panjang string nama perangkat
        let nameLength = Int(data[17])
        let expectedEnd = 18 + nameLength

        let friendlyName: String
        if expectedEnd <= data.count {
            let nameData = data.subdata(in: 18..<expectedEnd)
            friendlyName = String(data: nameData, encoding: .utf8) ?? "Samsung Device"
        } else {
            // Jika length byte melebihi panjang data, baca sisa buffer
            let nameData = data.subdata(in: 18..<data.count)
            friendlyName = String(data: nameData, encoding: .utf8) ?? "Samsung Device"
        }

        return ParsedEndpointInfo(
            friendlyName: friendlyName,
            deviceType: deviceType,
            salt: salt
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
}

public enum EndpointInfoParseError: Error, Equatable, Sendable {
    case invalidBase64Encoding
    case payloadTooShort(Int)
}
