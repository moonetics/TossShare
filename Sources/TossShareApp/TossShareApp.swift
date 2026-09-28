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
    private let receiverServer: NearbyReceiverServer

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

        let server = NearbyReceiverServer()
        self.receiverServer = server

        server.onRequestAcceptance = { session in
            let dummySender = PeerDevice(
                endpointId: session.peerEndpointId,
                friendlyName: "Samsung Device",
                deviceType: .phone,
                ipAddress: "127.0.0.1",
                port: 44445
            )
            return await TransferNotificationManager.shared.requestAcceptance(
                session: session,
                from: dummySender
            )
        }

        server.onTransferCompleted = { session in
            let dummySender = PeerDevice(
                endpointId: session.peerEndpointId,
                friendlyName: "Samsung Device",
                deviceType: .phone,
                ipAddress: "127.0.0.1",
                port: 44445
            )
            Task { @MainActor in
                let urls = session.items.compactMap { $0.localURL }
                TransferNotificationManager.shared.postTransferSuccess(
                    session: session,
                    from: dummySender,
                    savedURLs: urls
                )
            }
        }

        // Mulai scanning penemuan dan server penerima di background
        mdns.startDiscovery()
        ble.startMonitoring()
        try? server.start()
    }

    var body: some Scene {
        // Jendela Radar Utama (AirDrop-like Native Window)
        WindowGroup("TossShare") {
            RadarMainView(registry: registry, advisor: advisor)
                .task {
                    _ = await TransferNotificationManager.shared.requestAuthorization()
                }
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
