//
//  WireEncodingTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
@testable import TossShareCore

final class WireEncodingTests: XCTestCase {

    // MARK: - Length-Prefixed Framing Tests

    func testLengthPrefixedRoundtrip() {
        let payload = "Halo Samsung Quick Share!".data(using: .utf8)!
        let encoded = WireEncoding.encodeLengthPrefixed(payload)

        XCTAssertEqual(encoded.count, 4 + payload.count)

        var stream = encoded
        let decoded = WireEncoding.decodeLengthPrefixed(from: &stream)

        XCTAssertEqual(decoded, payload)
        XCTAssertTrue(stream.isEmpty, "Stream harus kosong setelah seluruh frame didekode.")
    }

    func testPartialStreamHandling() {
        let payload = "Paket data panjang untuk uji partial stream".data(using: .utf8)!
        let fullPacket = WireEncoding.encodeLengthPrefixed(payload)

        // Potong paket menjadi 2 bagian
        let halfCount = fullPacket.count / 2
        var partialStream = fullPacket.prefix(halfCount)

        // Belum lengkap -> harus mengembalikan nil tanpa merusak stream
        let firstAttempt = WireEncoding.decodeLengthPrefixed(from: &partialStream)
        XCTAssertNil(firstAttempt)
        XCTAssertEqual(partialStream.count, halfCount)

        // Tambahkan sisa data
        partialStream.append(fullPacket.suffix(from: halfCount))

        // Sekarang sudah lengkap -> harus berhasil
        let secondAttempt = WireEncoding.decodeLengthPrefixed(from: &partialStream)
        XCTAssertEqual(secondAttempt, payload)
        XCTAssertTrue(partialStream.isEmpty)
    }

    // MARK: - Varint 128 Tests

    func testVarintEncodingAndDecoding() {
        let testValues: [UInt64] = [0, 1, 42, 127, 128, 300, 16384, 2_097_152, UInt64.max]

        for value in testValues {
            let encoded = WireEncoding.encodeVarint(value)
            var offset = 0
            let decoded = WireEncoding.decodeVarint(from: encoded, offset: &offset)
            XCTAssertEqual(decoded, value, "Nilai varint \(value) gagal didekode dengan benar.")
            XCTAssertEqual(offset, encoded.count)
        }
    }

    // MARK: - Nearby Frame Codec Tests

    func testConnectionRequestFrameRoundtrip() throws {
        let frame = ConnectionRequestFrame(endpointId: "s24u", endpointName: "MacBook Pro M1", protocolVersion: 1)
        let encodedData = try NearbyFrameCodec.encode(type: .connectionRequest, payload: frame)

        var stream = encodedData
        guard let payloadData = WireEncoding.decodeLengthPrefixed(from: &stream) else {
            XCTFail("Gagal mengekstrak length-prefixed packet.")
            return
        }

        let (type, body) = try NearbyFrameCodec.decodeTypeAndPayload(from: payloadData)
        XCTAssertEqual(type, .connectionRequest)

        let decodedFrame = try NearbyFrameCodec.decodePayload(ConnectionRequestFrame.self, from: body)
        XCTAssertEqual(decodedFrame, frame)
    }

    func testIntroductionFrameRoundtrip() throws {
        let items = [
            TransferItem(fileName: "foto.jpg", mimeType: "image/jpeg", fileSize: 5_000_000),
            TransferItem(fileName: "video.mp4", mimeType: "video/mp4", fileSize: 100_000_000)
        ]
        let frame = IntroductionFrame(pin: "7492", items: items)
        let encodedData = try NearbyFrameCodec.encode(type: .introduction, payload: frame)

        var stream = encodedData
        let payloadData = try XCTUnwrap(WireEncoding.decodeLengthPrefixed(from: &stream))

        let (type, body) = try NearbyFrameCodec.decodeTypeAndPayload(from: payloadData)
        XCTAssertEqual(type, .introduction)

        let decodedFrame = try NearbyFrameCodec.decodePayload(IntroductionFrame.self, from: body)
        XCTAssertEqual(decodedFrame, frame)
        XCTAssertEqual(decodedFrame.items.count, 2)
        XCTAssertEqual(decodedFrame.pin, "7492")
    }

    func testAcceptanceFrameRoundtrip() throws {
        let frame = AcceptanceFrame(status: .accept)
        let encodedData = try NearbyFrameCodec.encode(type: .acceptance, payload: frame)

        var stream = encodedData
        let payloadData = try XCTUnwrap(WireEncoding.decodeLengthPrefixed(from: &stream))

        let (type, body) = try NearbyFrameCodec.decodeTypeAndPayload(from: payloadData)
        XCTAssertEqual(type, .acceptance)

        let decodedFrame = try NearbyFrameCodec.decodePayload(AcceptanceFrame.self, from: body)
        XCTAssertEqual(decodedFrame.status, .accept)
    }
}
