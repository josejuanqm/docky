//
//  MainWindowController.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit

final class MainWindowController: NSWindowController {
    private var dockEditorOverlayWindowController: DockEditorOverlayWindowController?
    private var dockEditorHintWindowController: DockEditorHintWindowController?
    private var launchpadOverlayWindowController: LaunchpadOverlayWindowController?
    private var smartOrganizeProgressChipWindowController: SmartOrganizeProgressChipWindowController?
    private var windowSwitcherOverlayWindowController: WindowSwitcherOverlayWindowController?
    private var startMenuOverlayWindowController: StartMenuOverlayWindowController?
    private var profileSwitcherWindowController: ProfileSwitcherWindowController?
    private var launchpadInspectorWindowController: LaunchpadInspectorWindowController?

    override init(window: NSWindow?) {
        super.init(window: window)

        guard let mainWindow = window as? MainWindow else {
            return
        }

        dockEditorOverlayWindowController = DockEditorOverlayWindowController(mainWindow: mainWindow)
        dockEditorHintWindowController = DockEditorHintWindowController(mainWindow: mainWindow)
        launchpadOverlayWindowController = LaunchpadOverlayWindowController(mainWindow: mainWindow)
        smartOrganizeProgressChipWindowController = SmartOrganizeProgressChipWindowController(mainWindow: mainWindow)
        windowSwitcherOverlayWindowController = WindowSwitcherOverlayWindowController(mainWindow: mainWindow)
        startMenuOverlayWindowController = StartMenuOverlayWindowController(mainWindow: mainWindow)
        profileSwitcherWindowController = ProfileSwitcherWindowController(mainWindow: mainWindow)
        launchpadInspectorWindowController = LaunchpadInspectorWindowController()
        _ = StartMenuService.shared
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        dockEditorHintWindowController?.scheduleInitialPresentation()
    }
}
