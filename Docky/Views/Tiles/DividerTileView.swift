//
//  DividerTileView.swift
//  Docky
//

import SwiftUI

struct DividerTileView: View {
    let tileID: String
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        divider
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background {
                if !isPinnedCustomDivider {
                    ContextActionMenuPresenter { _ in
                        dividerContextActions
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
            .action("Edit Dock...") {
                DockEditModeService.shared.enter()
            },
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
        dockSettings.tileSize * 0.25
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private var isPinnedCustomDivider: Bool {
        tileID.hasPrefix("pinned:")
    }
}
