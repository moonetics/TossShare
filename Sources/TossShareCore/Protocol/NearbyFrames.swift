//
//  NearbyFrames.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation

/// Tipe frame yang dipertukarkan pada lapisan protokol aplikasi Quick Share.
public enum NearbyFrameType: UInt8, Codable, Sendable {
    case connectionRequest = 1
    case introduction      = 2
    case acceptance        = 3
}

/// Status respon penerimaan berkas dari target.
public enum AcceptanceStatus: String, Codable, Sendable {
    case accept
    case reject
}

// MARK: - Frame Models

/// Frame inisiasi koneksi aplikasi yang dikirimkan setelah jabat tangan UKEY2 sukses.
public struct ConnectionRequestFrame: Codable, Sendable, Equatable {
    public let endpointId: String
    public let endpointName: String
    public let protocolVersion: Int

    public init(endpointId: String, endpointName: String, protocolVersion: Int = 1) {
        self.endpointId = endpointId
        self.endpointName = endpointName
        self.protocolVersion = protocolVersion
    }
}

/// Frame perkenalan yang membawa manifest berkas yang akan ditransfer beserta token PIN.
public struct IntroductionFrame: Codable, Sendable, Equatable {
    public let pin: String
    public let items: [TransferItem]

    public init(pin: String, items: [TransferItem]) {
        self.pin = pin
        self.items = items
    }
}

/// Frame respon dari perangkat target apakah bersedia menerima atau menolak transfer.
public struct AcceptanceFrame: Codable, Sendable, Equatable {
    public let status: AcceptanceStatus

    public init(status: AcceptanceStatus) {
        self.status = status
    }
}

// MARK: - Frame Envelope & Serialization

/// Pembungkus frame terpadu untuk transmisi soket nirkabel.
public struct NearbyFrameCodec: Sendable {

    /// Mengodekan frame ke dalam format biner terbingkai: Type (1 Byte) + JSON Payload (N Bytes).
    public static func encode<T: Encodable>(type: NearbyFrameType, payload: T) throws -> Data {
        let jsonEncoder = JSONEncoder()
        let bodyData = try jsonEncoder.encode(payload)
        var packet = Data([type.rawValue])
        packet.append(bodyData)
        return WireEncoding.encodeLengthPrefixed(packet)
    }

    /// Mendekodekan muatan frame biner menjadi pasangan tipe dan data mentah.
    public static func decodeTypeAndPayload(from data: Data) throws -> (NearbyFrameType, Data) {
        guard let firstByte = data.first,
              let type = NearbyFrameType(rawValue: firstByte) else {
            throw NearbyFrameError.unknownFrameType
        }
        let payload = data.dropFirst()
        return (type, Data(payload))
    }

    /// Mendekodekan payload spesifik.
    public static func decodePayload<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let jsonDecoder = JSONDecoder()
        return try jsonDecoder.decode(T.self, from: data)
    }
}

public enum NearbyFrameError: Error, Equatable, Sendable {
    case unknownFrameType
    case corruptPayload
}
