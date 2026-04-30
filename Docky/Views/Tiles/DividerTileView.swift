//
//  DividerTileView.swift
//  Docky
//

import SwiftUI

struct DividerTileView: View {
    let tileID: String
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var layout = DockLayoutService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        GeometryReader { proxy in
            divider
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var dividerContextActions: [ContextAction] {
        [
            .action(preferences.autohidesWindow ? "Turn Hiding Off" : "Turn Hiding On") {
                preferences.autohidesWindow.toggle()
            },
            .submenu("Position on Screen", children: positionActions),
            .divider,
            .action("Smart Organize Pinned Items") {
                TileStore.shared.smartOrganizePinnedItems()
            },
            .divider,
            .action("Edit Dock...") {
                DockEditModeService.shared.enter()
            },
            .submenu("Troubleshoot", children: troubleshootActions),
            .divider,
            .action("Settings...") {
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
            },
            .divider,
            .action("Quit Docky", isDestructive: true) {
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
            .action("Sync Dock") {
                DockSettingsService.shared.refresh()
                TileStore.shared.refresh()
            }
        ]
    }

    @ViewBuilder
    private var divider: some View {
        if position.isVertical {
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

    private var lineInset: CGFloat {
        layout.scaled(dockSettings.displayTileSize) * 0.25
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private var isPinnedCustomDivider: Bool {
        tileID.hasPrefix("pinned:")
    }
}
