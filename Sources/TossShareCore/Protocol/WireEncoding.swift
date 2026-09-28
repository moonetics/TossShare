//
//  WireEncoding.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation

/// Utilitas serialisasi protokol biner tingkat rendah (4-byte length-prefix dan protobuf varint).
public struct WireEncoding: Sendable {

    // MARK: - Length-Prefixed Framing (4-Byte Big-Endian)

    /// Membungkus muatan biner dengan 4-byte header panjang (Big-Endian).
    public static func encodeLengthPrefixed(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)
        return packet
    }

    /// Membaca satu paket lengkap dari buffer aliran data.
    /// Jika data belum lengkap (< 4 byte atau payload belum utuh), mengembalikan nil tanpa memotong buffer.
    public static func decodeLengthPrefixed(from stream: inout Data) -> Data? {
        guard stream.count >= 4 else { return nil }
        let length = stream.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let totalPacketLength = 4 + Int(length)

        guard stream.count >= totalPacketLength else { return nil }

        let payload = stream.subdata(in: 4..<totalPacketLength)
        stream.removeSubrange(0..<totalPacketLength)
        return payload
    }

    // MARK: - Protobuf Varint 128 Encoding & Decoding

    /// Mengodekan nilai 64-bit integer ke dalam representasi Varint (LEB128).
    public static func encodeVarint(_ value: UInt64) -> Data {
        var val = value
        var bytes = [UInt8]()
        while val >= 0x80 {
            bytes.append(UInt8(val & 0x7F) | 0x80)
            val >>= 7
        }
        bytes.append(UInt8(val & 0x7F))
        return Data(bytes)
    }

    /// Mendekodekan nilai Varint dari stream data pada offset tertentu.
    public static func decodeVarint(from data: Data, offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift > 63 {
                return nil // Overflow
            }
        }
        return nil // Incomplete
    }

    // MARK: - Protobuf Tag Helpers

    /// Membuat wire tag: (fieldNumber << 3) | wireType
    public static func makeTag(fieldNumber: Int, wireType: Int) -> UInt64 {
        return (UInt64(fieldNumber) << 3) | UInt64(wireType & 0x07)
    }

    /// Mengodekan string UTF-8 sebagai field protobuf bertipe Length-Delimited (wireType 2).
    public static func encodeStringField(fieldNumber: Int, string: String) -> Data {
        let stringData = string.data(using: .utf8) ?? Data()
        var result = encodeVarint(makeTag(fieldNumber: fieldNumber, wireType: 2))
        result.append(encodeVarint(UInt64(stringData.count)))
        result.append(stringData)
        return result
    }

    /// Mengodekan raw Data sebagai field protobuf bertipe Length-Delimited (wireType 2).
    public static func encodeDataField(fieldNumber: Int, data: Data) -> Data {
        var result = encodeVarint(makeTag(fieldNumber: fieldNumber, wireType: 2))
        result.append(encodeVarint(UInt64(data.count)))
        result.append(data)
        return result
    }

    /// Mengodekan integer sebagai field protobuf bertipe Varint (wireType 0).
    public static func encodeUInt64Field(fieldNumber: Int, value: UInt64) -> Data {
        var result = encodeVarint(makeTag(fieldNumber: fieldNumber, wireType: 0))
        result.append(encodeVarint(value))
        return result
    }
}
