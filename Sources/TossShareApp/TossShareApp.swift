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

    @StateObject private var registry: DeviceRegistry
    @StateObject private var advisor: ConnectivityAdvisor

    private let healthMonitor: NetworkHealthMonitor
    private let mdnsService: MDNSDiscoveryService
    private let bleMonitor: BLEProximityMonitor

    init() {
        let newRegistry = DeviceRegistry()
        let newHealthMonitor = NetworkHealthMonitor()
        let newAdvisor = ConnectivityAdvisor(healthMonitor: newHealthMonitor)

        _registry = StateObject(wrappedValue: newRegistry)
        _advisor = StateObject(wrappedValue: newAdvisor)

        self.healthMonitor = newHealthMonitor
        let mdns = MDNSDiscoveryService(registry: newRegistry)
        self.mdnsService = mdns
        let ble = BLEProximityMonitor(registry: newRegistry)
        self.bleMonitor = ble

        // Mulai scanning penemuan di background
        mdns.startDiscovery()
        ble.startMonitoring()
    }

    var body: some Scene {
        // Jendela Radar Utama (AirDrop-like Native Window)
        WindowGroup("TossShare") {
            RadarMainView(registry: registry, advisor: advisor)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        // Menu Bar Status Item & Drop Zone
        MenuBarExtra("TossShare", systemImage: "arrow.triangle.swap") {
            MenuBarPopoverView(registry: registry, advisor: advisor) {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
