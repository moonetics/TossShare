//
//  DeviceAvatarNode.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI

public enum DeviceNodeType: String, Sendable, CaseIterable {
    case phone
    case tablet
    case laptop
    case unknown

    public var systemImageName: String {
        switch self {
        case .phone:
            return "iphone.gen3"
        case .tablet:
            return "ipad.gen2"
        case .laptop:
            return "laptopcomputer"
        case .unknown:
            return "display"
        }
    }
}

/// Avatar node interaktif yang mewakili perangkat terdeteksi di dalam Radar UI TossShare.
public struct DeviceAvatarNode: View {
    public let name: String
    public let type: DeviceNodeType
    public let statusSubtitle: String
    public let isHighlighted: Bool
    public let onTap: (() -> Void)?

    @State private var isHovered: Bool = false

    public init(
        name: String,
        type: DeviceNodeType = .phone,
        statusSubtitle: String = "Siap Menerima",
        isHighlighted: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.name = name
        self.type = type
        self.statusSubtitle = statusSubtitle
        self.isHighlighted = isHighlighted
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            TossShareHaptics.performDropSnapped()
            onTap?()
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                // Circle Avatar Icon
                ZStack {
                    // Pendaran hover / highlighted
                    if isHovered || isHighlighted {
                        Circle()
                            .fill(Theme.Colors.samsungCyan.opacity(0.25))
                            .frame(width: 68, height: 68)
                            .blur(radius: 6)
                    }

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isHovered || isHighlighted
                                        ? Theme.Colors.samsungCyan
                                        : Theme.Colors.borderHairline,
                                    lineWidth: isHovered || isHighlighted ? 2.0 : 1.0
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(0.12),
                            radius: 6,
                            x: 0,
                            y: 3
                        )

                    Image(systemName: type.systemImageName)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(
                            isHovered || isHighlighted
                                ? Theme.Colors.gradientBrand
                                : LinearGradient(
                                    colors: [Color.primary.opacity(0.85), Color.primary.opacity(0.65)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                }

                // Label Nama Perangkat
                VStack(spacing: 2) {
                    Text(name)
                        .font(Theme.Typography.deviceTitle)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(statusSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 110)
            }
            .contentShape(Rectangle())
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(Theme.Animation.springSnappy, value: isHovered)
            .animation(Theme.Animation.springSnappy, value: isHighlighted)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                TossShareHaptics.performDropSnapped()
            }
        }
        .frame(minWidth: 80, minHeight: 80)
    }
}
