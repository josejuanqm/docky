//
//  AppDelegate.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    private var mainWindowController: MainWindowController?
    private var permissionsWindowController: PermissionsWindowController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window?.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        configureMainMenu()

        PermissionsService.shared.refresh()
        if PermissionsService.shared.setupComplete {
            showMainWindow()
        } else {
            showPermissionsWindow(steps: PermissionsService.shared.setupPermissions)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)

        if settingsWindowController == nil {
            let controller = SettingsWindowController()
            controller.onClose = { [weak self] in
                NSApp.setActivationPolicy(.accessory)
                self?.settingsWindowController = nil
            }
            settingsWindowController = controller
        }

        settingsWindowController?.showWindow(sender)
        settingsWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPermissionsWindow(steps: [Permission]) {
        NSApp.setActivationPolicy(.regular)
        let controller = PermissionsWindowController(steps: steps)
        controller.onComplete = { [weak self] in
            NSApp.setActivationPolicy(.accessory)
            self?.permissionsWindowController = nil
            self?.showMainWindow()
        }
        permissionsWindowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMainWindow() {
        mainWindowController = makeMainWindowController()
        mainWindowController?.showWindow(self)
    }

    private func makeMainWindowController() -> MainWindowController? {
        var topLevelObjects: NSArray?
        let didLoadNib = Bundle.main.loadNibNamed(
            "MainWindow",
            owner: nil,
            topLevelObjects: &topLevelObjects
        )

        guard
            didLoadNib,
            let mainWindow = (topLevelObjects as? [Any])?.first(where: { $0 is MainWindow }) as? MainWindow
        else {
            assertionFailure("Failed to load MainWindow.xib")
            return nil
        }

        return MainWindowController(window: mainWindow)
    }

    private func configureMainMenu() {
        let appMenu = NSApp.mainMenu?.items.first?.submenu
        guard let item = appMenu?.item(withTitle: "Preferences…") ?? appMenu?.item(withTitle: "Settings…") else {
            return
        }
        item.title = "Settings…"
        item.action = #selector(showSettingsWindow(_:))
        item.target = self
    }
}
