//
//  WindowContextActions.swift
//  Docky
//
//  Shared builder for the per-window section of context menus shown in the
//  hover preview popover and the Cmd-Tab switcher overlay. Mirrors the macOS
//  Window menu (Minimize / Zoom / Fill / Center / Move & Resize) using AX
//  geometry under the hood — no menu-walking, so this works for every app
//  that responds to AX position/size, not just Cocoa apps with a standard
//  Window menu.
//

import AppKit

@MainActor
func windowMenuContextActions(
    for window: AppWindow,
    dismiss: @escaping () -> Void
) -> [ContextAction] {
    let workspace = WorkspaceService.shared

    func run(_ action: @escaping (AppWindow) -> Bool) -> () -> Void {
        return {
            dismiss()
            _ = action(window)
        }
    }

    return [
        .action(String(localized: "Minimize"), image: contextMenuSymbol("minus.circle"), handler: run(workspace.minimize(window:))),
        .action(String(localized: "Zoom"), image: contextMenuSymbol("arrow.up.left.and.arrow.down.right"), handler: run(workspace.zoom(window:))),
        .action(String(localized: "Fill"), image: contextMenuSymbol("rectangle.fill"), handler: run(workspace.fill(window:))),
        .action(String(localized: "Center"), image: contextMenuSymbol("rectangle.center.inset.filled"), handler: run(workspace.center(window:))),
        .submenu(String(localized: "Move & Resize"), children: [
            .action(String(localized: "Left"), image: contextMenuSymbol("rectangle.lefthalf.filled"), handler: run(workspace.fillLeftHalf(window:))),
            .action(String(localized: "Right"), image: contextMenuSymbol("rectangle.righthalf.filled"), handler: run(workspace.fillRightHalf(window:))),
            .action(String(localized: "Top"), image: contextMenuSymbol("rectangle.tophalf.filled"), handler: run(workspace.fillTopHalf(window:))),
            .action(String(localized: "Bottom"), image: contextMenuSymbol("rectangle.bottomhalf.filled"), handler: run(workspace.fillBottomHalf(window:))),
            .divider,
            .action(String(localized: "Top Left"), image: contextMenuSymbol("arrow.up.left"), handler: run(workspace.fillTopLeftQuarter(window:))),
            .action(String(localized: "Top Right"), image: contextMenuSymbol("arrow.up.right"), handler: run(workspace.fillTopRightQuarter(window:))),
            .action(String(localized: "Bottom Left"), image: contextMenuSymbol("arrow.down.left"), handler: run(workspace.fillBottomLeftQuarter(window:))),
            .action(String(localized: "Bottom Right"), image: contextMenuSymbol("arrow.down.right"), handler: run(workspace.fillBottomRightQuarter(window:))),
        ]),
    ]
}
