//
//  LaunchpadInspectorService.swift
//  Docky
//
//  Drives a detached settings panel that floats above the Launchpad
//  overlay so the user can live-edit grid columns, icon size, etc. and
//  see the changes immediately on the underlying grid. The state lives
//  here so the SwiftUI overlay can toggle it from a chrome button and
//  `LaunchpadInspectorWindowController` can react.
//

import Combine
import Foundation

final class LaunchpadInspectorService: ObservableObject {
    static let shared = LaunchpadInspectorService()

    @Published private(set) var isPresented = false

    private init() {}

    func toggle() { isPresented ? dismiss() : present() }

    func present() {
        guard !isPresented else { return }
        isPresented = true
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
    }
}
