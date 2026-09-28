//
//  DesignTokenTests.swift
//  TossShareCoreTests
//
//  Created for TossShare for macOS.
//

import XCTest
import SwiftUI
@testable import TossShareCore
@testable import TossShareUI

final class DesignTokenTests: XCTestCase {
    func testByteFormatting() {
        let oneKB: Int64 = 1024
        let formattedKB = Theme.Formatters.formatBytes(oneKB)
        XCTAssertFalse(formattedKB.isEmpty)

        let oneGB: Int64 = 1_073_741_824
        let formattedGB = Theme.Formatters.formatBytes(oneGB)
        XCTAssertTrue(formattedGB.contains("GB") || formattedGB.contains("G"))
    }

    func testSpeedFormatting() {
        let zeroSpeed = Theme.Formatters.formatSpeed(0)
        XCTAssertEqual(zeroSpeed, "0 KB/s")

        let fiftyMB: Double = 52_428_800 // 50 MB/s
        let formattedSpeed = Theme.Formatters.formatSpeed(fiftyMB)
        XCTAssertEqual(formattedSpeed, "50.0 MB/s")

        let halfMB: Double = 512_000
        let formattedHalf = Theme.Formatters.formatSpeed(halfMB)
        XCTAssertTrue(formattedHalf.contains("KB/s"))
    }

    func testDeviceNodeTypes() {
        XCTAssertEqual(DeviceNodeType.allCases.count, 4)
        XCTAssertEqual(DeviceNodeType.phone.systemImageName, "iphone.gen3")
        XCTAssertEqual(DeviceNodeType.tablet.systemImageName, "ipad.gen2")
        XCTAssertEqual(DeviceNodeType.laptop.systemImageName, "laptopcomputer")
        XCTAssertEqual(DeviceNodeType.unknown.systemImageName, "display")
    }

    func testDesignTokensValues() {
        XCTAssertGreaterThan(Theme.Animation.radarPulseDuration, 0)
        XCTAssertEqual(Theme.Spacing.xs, 8)
        XCTAssertEqual(Theme.Spacing.md, 16)
        XCTAssertEqual(Theme.Radii.card, 14)
    }
}
