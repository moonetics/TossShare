//
//  PulsingRing.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI

/// Lingkaran radar konsentris bernapas dengan pendaran halus untuk visualisasi pemindaian nirkabel.
public struct PulsingRing: View {
    private let delay: Double
    private let maxScale: CGFloat
    private let strokeColor: Color
    private let lineWidth: CGFloat

    @State private var isPulsing: Bool = false

    public init(
        delay: Double = 0.0,
        maxScale: CGFloat = 2.4,
        strokeColor: Color = Theme.Colors.samsungCyan,
        lineWidth: CGFloat = 1.5
    ) {
        self.delay = delay
        self.maxScale = maxScale
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Circle()
            .strokeBorder(
                strokeColor.opacity(isPulsing ? 0.02 : 0.45),
                lineWidth: lineWidth
            )
            .scaleEffect(isPulsing ? maxScale : 0.6)
            .animation(
                Animation.easeOut(duration: Theme.Animation.radarPulseDuration)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
            .allowsHitTesting(false)
    }
}
