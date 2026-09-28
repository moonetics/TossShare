//
//  ConnectivityAdvisor.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Foundation
import Combine

/// Mode rekomendasi konektivitas alternatif saat jalur Wi-Fi LAN standar terhambat.
public enum FallbackMode: String, Sendable, CaseIterable {
    case mobileHotspot
    case usbTethering
}

/// Penasihat konektivitas cerdas yang memicu kartu panduan FallbackCard saat jaringan terisolasi.
@MainActor
public final class ConnectivityAdvisor: ObservableObject {

    @Published public var shouldShowFallbackCard: Bool = false
    @Published public var recommendedFallbackMode: FallbackMode = .mobileHotspot

    private let healthMonitor: NetworkHealthMonitor

    public init(healthMonitor: NetworkHealthMonitor) {
        self.healthMonitor = healthMonitor
        updateStatus()

        healthMonitor.onStatusChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateStatus()
            }
        }
    }

    private func updateStatus() {
        if healthMonitor.isAPIsolationSuspected {
            shouldShowFallbackCard = true
            recommendedFallbackMode = healthMonitor.isHotspotOrTethered ? .usbTethering : .mobileHotspot
        } else {
            shouldShowFallbackCard = false
        }
    }

    /// Menutup kartu saran panduan secara manual oleh pengguna.
    public func dismissFallbackCard() {
        shouldShowFallbackCard = false
    }

    /// Mengaktifkan mode simulasi AP Isolation untuk demonstrasi UI.
    public func simulateAPIsolation(enabled: Bool) {
        healthMonitor.simulateAPIsolation(enabled: enabled)
        updateStatus()
    }
}
