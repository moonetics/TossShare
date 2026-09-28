//
//  TossShareHaptics.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import AppKit

/// Helper thread-safe untuk memicu umpan balik haptik (Haptic Feedback) pada trackpad Mac.
@MainActor
public enum TossShareHaptics {
    /// Memicu haptik untuk aksi berhasil (misal: transfer selesai atau file diterima).
    public static func performSuccess() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }

    /// Memicu haptik untuk peringatan atau kegagalan (misal: koneksi terputus atau AP isolation).
    public static func performWarning() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }

    /// Memicu haptik saat kursor menyeret file ke atas avatar perangkat (Drop Target snapped).
    public static func performDropSnapped() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
    }
}
