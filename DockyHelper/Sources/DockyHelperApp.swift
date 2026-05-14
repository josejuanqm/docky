//
//  DockyHelperApp.swift
//  DockyHelper
//
//  Entry point for the Docky Helper daemon. The bundle is started
//  on demand by launchd when Docky.app's `NSXPCConnection` to
//  `gt.quintero.Docky.Helper` resolves the service.
//
//  No SwiftUI UI: this is a faceless agent (LSUIElement = true in
//  Info.plist). The only visible affordance is a future menu-bar
//  status item ("Docky Helper is running") added when we ship.
//

import AppKit
import SwiftUI

@main
struct DockyHelperApp: App {
    @NSApplicationDelegateAdaptor(DockyHelperAppDelegate.self) var delegate

    var body: some Scene {
        // Faceless: no Settings or WindowGroup scene. The XPC
        // listener does all the work; the app process exists only
        // so launchd has something to keep alive.
        Settings { EmptyView() }
    }
}

final class DockyHelperAppDelegate: NSObject, NSApplicationDelegate {
    private let listener = HelperListener()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        listener.start()
    }
}
