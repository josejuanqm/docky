//
//  DividerTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct DividerTileView: View {
    let tileID: String
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var layout = DockLayoutService.shared
    @Bindable private var preferences = DockyPreferences.shared

    var body: some View {
        GeometryReader { proxy in
            divider(globalFrame: proxy.frame(in: .global))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: dividerOffsetVector.width, y: dividerOffsetVector.height)
                .background(.black.opacity(0.001))
                .contentShape(Path(CGRect(origin: .zero, size: proxy.size)))
                .background {
                    if !isPinnedCustomDivider {
                        ContextActionMenuPresenter { _ in
                            dividerContextActions
                        }
                    }
                }
        }
    }

    private var dividerOffsetVector: CGSize {
        let amount = preferences.dividerOffset
        if position.isVertical {
            return CGSize(width: amount, height: 0)
        } else {
            return CGSize(width: 0, height: -amount)
        }
    }

    private var dividerContextActions: [ContextAction] {
        [
            .action(preferences.autohidesWindow ? "Turn Hiding Off" : "Turn Hiding On") {
                preferences.autohidesWindow.toggle()
            },
            .submenu(String(localized: "Position on Screen"), children: positionActions),
            .divider,
//            .action("Smart Organize Pinned Items") {
//                TileStore.shared.smartOrganizePinnedItems()
//            },
            .divider,
            .action(String(localized: "Edit Dock...")) {
                DockEditModeService.shared.enter()
            },
            .submenu(String(localized: "Troubleshoot"), children: troubleshootActions),
            .divider,
            .action(String(localized: "About Docky")) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            },
            .action(String(localized: "Settings...")) {
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
            },
            .divider,
            .action(String(localized: "Quit Docky"), isDestructive: true) {
                NSApp.terminate(nil)
            }
        ]
    }

    private var positionActions: [ContextAction] {
        DockWindowPosition.allCases.map { position in
            .action(position.title, isOn: preferences.windowPosition == position) {
                preferences.windowPosition = position
            }
        }
    }

    private var troubleshootActions: [ContextAction] {
        [
            .action(String(localized: "Sync Dock")) {
                DockSettingsService.shared.refresh()
                TileStore.shared.refresh()
            }
        ]
    }

    @ViewBuilder
    private func divider(globalFrame: CGRect) -> some View {
        let positionClass = positionClass(globalFrame: globalFrame)

        if let resolvedImage = preferences.resolvedDividerImage(forPositionClass: positionClass),
           let nsImage = NSImage(contentsOf: resolvedImage.url) {
            customImageDivider(nsImage: nsImage, mirrored: resolvedImage.mirrored)
        } else if position.isVertical {
            Rectangle()
                .fill(.primary.opacity(0.2))
                .frame(height: 1)
        } else {
            Rectangle()
                .fill(.primary.opacity(0.2))
                .frame(width: 1)
                .padding(.vertical, lineInset)
        }
    }

    @ViewBuilder
    private func customImageDivider(nsImage: NSImage, mirrored: Bool) -> some View {
        let imageScale = max(0.25, preferences.dividerImageScale)
        Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(x: (mirrored ? -1 : 1) * imageScale, y: imageScale)
            .rotationEffect(.degrees(position.isVertical ? 90 : 0))
            .padding(position.isVertical ? .horizontal : .vertical, lineInset)
    }

    private func positionClass(globalFrame: CGRect) -> DockDividerPositionClass {
        let canvas = layout.tileCanvasFrame
        guard canvas.width > 0, canvas.height > 0 else { return .center }

        let relative: CGFloat
        if position.isVertical {
            relative = (globalFrame.midY - canvas.minY) / canvas.height
        } else {
            relative = (globalFrame.midX - canvas.minX) / canvas.width
        }

        switch relative {
        case ..<(1.0 / 3.0):
            return .left
        case (2.0 / 3.0)...:
            return .right
        default:
            return .center
        }
    }

    private var lineInset: CGFloat {
        let fraction = min(max(preferences.dividerPaddingFraction, 0), 0.5)
        return layout.scaled(dockSettings.displayTileSize) * fraction
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private var isPinnedCustomDivider: Bool {
        tileID.hasPrefix("pinned:")
    }
}
