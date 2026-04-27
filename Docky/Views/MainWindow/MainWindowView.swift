//
//  MainWindowView.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit
import SwiftUI

struct MainWindowView: View {
    private let borderWidth: CGFloat = 1

    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var layoutService = DockLayoutService.shared

    var body: some View {
        let cornerRadius = effectiveCornerRadius

        TileContainerView()
            .background {
                backgroundFill(cornerRadius: cornerRadius)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if !preferences.disablesGlassLook {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: borderWidth / 2)
                        .strokeBorder(borderGradient, lineWidth: borderWidth)
                }
            }
            .compositingGroup()
    }

    @ViewBuilder
    private func backgroundFill(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .overlay {
                if let backgroundImage = resolvedBackgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(nsColor: preferences.effectiveWindowTintColor)
                        .opacity(preferences.effectiveWindowTintOpacity)
                }
            }
            .clipped()
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.35),
                Color.white.opacity(0.12),
                Color.white.opacity(0.05),
                Color.white.opacity(0.12),
                Color.white.opacity(0.28),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var effectiveCornerRadius: CGFloat {
        preferences.windowClipShape.resolvedCornerRadius(
            base: preferences.windowCornerRadius,
            maximum: maximumCornerRadius
        )
    }

    private var maximumCornerRadius: CGFloat {
        let iconHeight = layoutService.scaled(dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize)
        return (iconHeight + layoutService.scaled(preferences.tileVerticalPadding) * 2) / 2
    }

    private var resolvedBackgroundImage: NSImage? {
        guard let backgroundImageURL = preferences.effectiveWindowBackgroundImageURL else {
            return nil
        }

        return NSImage(contentsOf: backgroundImageURL)
    }
}

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
