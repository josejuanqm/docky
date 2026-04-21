//
//  MainWindowController.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit

final class MainWindowController: NSWindowController {
    private var dockEditorOverlayWindowController: DockEditorOverlayWindowController?

    override init(window: NSWindow?) {
        super.init(window: window)

        guard let mainWindow = window as? MainWindow else {
            return
        }

        dockEditorOverlayWindowController = DockEditorOverlayWindowController(mainWindow: mainWindow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
