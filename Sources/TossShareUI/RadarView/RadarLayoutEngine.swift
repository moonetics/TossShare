//
//  RadarLayoutEngine.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import Foundation
import CoreGraphics
import TossShareCore

/// Menghitung tata letak geometris polar untuk menempatkan avatar perangkat target pada orbit radar dinamis.
public struct RadarLayoutEngine: Sendable {

    public struct NodePosition: Equatable, Sendable {
        public let endpointId: String
        public let point: CGPoint
        public let radius: CGFloat
        public let angle: Double

        public init(endpointId: String, point: CGPoint, radius: CGFloat, angle: Double) {
            self.endpointId = endpointId
            self.point = point
            self.radius = radius
            self.angle = angle
        }
    }

    /// Menghitung posisi seluruh perangkat di sekeliling pusat radar.
    /// Perangkat dengan RSSI lebih kuat (misal -40 dBm) berada di cincin dalam; RSSI lemah (-85 dBm) di cincin luar.
    public static func computePositions(
        for devices: [PeerDevice],
        center: CGPoint,
        innerRadius: CGFloat = 105,
        outerRadius: CGFloat = 195
    ) -> [NodePosition] {
        guard !devices.isEmpty else { return [] }

        let count = devices.count
        var positions: [NodePosition] = []

        for (index, device) in devices.enumerated() {
            // 1. Hitung Radius Berdasarkan RSSI
            let radius: CGFloat
            if let rssi = device.rssi {
                // Rentang normal BLE RSSI: -35 (sangat dekat) ke -90 (sangat jauh)
                let clampedRSSI = max(-90, min(-35, rssi))
                let proximityFactor = CGFloat(clampedRSSI - (-90)) / CGFloat((-35) - (-90)) // 0.0 (jauh) .. 1.0 (dekat)
                radius = outerRadius - (proximityFactor * (outerRadius - innerRadius))
            } else {
                radius = (innerRadius + outerRadius) / 2
            }

            // 2. Hitung Sudut Angular (Merata 360 Derajat, mulai dari jam 12 / -pi/2)
            let angle: Double
            if count == 1 {
                angle = -.pi / 2
            } else {
                angle = ((2.0 * .pi / Double(count)) * Double(index)) - (.pi / 2)
            }

            // 3. Konversi Polar ke Cartesian
            let x = center.x + radius * CGFloat(cos(angle))
            let y = center.y + radius * CGFloat(sin(angle))

            positions.append(NodePosition(
                endpointId: device.endpointId,
                point: CGPoint(x: x, y: y),
                radius: radius,
                angle: angle
            ))
        }

        return positions
    }
}
