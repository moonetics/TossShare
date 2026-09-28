//
//  TossShareExtension.swift
//  TossShareExtension
//
//  Created for TossShare for macOS.
//

import Foundation
import TossShareCore

/// Kerangka modul untuk integrasi Finder Share Extension (klik kanan > Share > TossShare).
public final class TossShareExtensionContext: Sendable {
    public static let shared = TossShareExtensionContext()

    public init() {}

    public func prepareSharingSession(for itemURLs: [URL]) -> String {
        return "TossShare Session for \(itemURLs.count) item(s)"
    }
}
