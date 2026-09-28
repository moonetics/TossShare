//
//  TossShareApp.swift
//  TossShareApp
//
//  Created for TossShare for macOS.
//

import SwiftUI
import TossShareCore
import TossShareUI

@main
struct TossShareApp: App {
    var body: some Scene {
        WindowGroup {
            TossShareRadarPlaceholderView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra("TossShare", systemImage: "paperplane.fill") {
            Button("Buka Radar TossShare") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Keluar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
