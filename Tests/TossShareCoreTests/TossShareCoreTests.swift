//
//  TossShareCoreTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
@testable import TossShareCore

final class TossShareCoreTests: XCTestCase {
    func testModuleConstants() {
        XCTAssertEqual(TossShareCore.version, "1.0.0")
        XCTAssertEqual(TossShareCore.mdnsServiceType, "_FC9F5ED42C8A._tcp.")
        XCTAssertTrue(TossShareCore.bleServiceUUIDStrings.contains("FE2C"))
        XCTAssertTrue(TossShareCore.bleServiceUUIDStrings.contains("FC12"))
        XCTAssertTrue(TossShareCore.bleServiceUUIDStrings.contains("FEF3"))
    }
}
