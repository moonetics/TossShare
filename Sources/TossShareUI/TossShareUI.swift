//
//  TossShareUI.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI
import TossShareCore

/// Namespace untuk komponen antarmuka visual TossShare.
public enum TossShareUI {
    public static let moduleName = "TossShareUI"
}

/// Tampilan placeholder radar untuk inisialisasi awal UI Phase 0.
public struct TossShareRadarPlaceholderView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.accentColor)
            Text("TossShare Radar")
                .font(.headline)
            Text("Siap memindai perangkat Samsung terdekat...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 240)
    }
}
