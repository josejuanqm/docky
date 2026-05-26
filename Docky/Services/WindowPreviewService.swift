//
//  WindowPreviewService.swift
//  Docky
//
//  State backing the per-tile hover window preview popover.
//  WindowSwitcherService is the global Cmd-Tab-style switcher; this is the
//  smaller hover-driven counterpart anchored to a single app tile.
//  Visual layout choice is shared (`WindowSwitcherLayout`), and previews
//  are sourced from the same WorkspaceService cache so we don't double-pay
//  for capture.
//

import AppKit
import Combine

@MainActor
final class WindowPreviewService: ObservableObject {
    static let shared = WindowPreviewService()

    @Published private(set) var windows: [AppWindow] = []
    @Published private(set) var selectedWindowIdentifier: String?
    @Published private(set) var isContextMenuPresented = false
    @Published private(set) var presentedSourceTileID: String?
    @Published private(set) var presentedBundleIdentifier: String?

    private(set) var windowPreviews: [String: NSImage] = [:]

    var resolvedLayout: WindowSwitcherLayout {
        let canCapture = PermissionsService.shared.screenCapture == .granted
        return DockyPreferences.shared.windowPreviewLayout
            .resolved(canCaptureThumbnails: canCapture)
    }

    private init() {}

    /// Returns true when the popover should present. Captures the current
    /// window list and freezes preview images so the popover stays stable
    /// while the user is interacting with it. Re-presenting for the same
    /// tile id is a no-op so cursor jitter doesn't reset selection.
    @discardableResult
    func present(forBundleIdentifier bundleID: String, sourceTileID: String) -> Bool {
        present(forBundleIdentifiers: [bundleID], sourceTileID: sourceTileID)
    }

    /// Multi-bundle variant used by app-folder tiles to surface windows from
    /// every app inside the folder in a single preview popover.
    @discardableResult
    func present(forBundleIdentifiers bundleIDs: [String], sourceTileID: String) -> Bool {
        // Per-tile preview is part of the `.windowSwitcher` Pro feature, paired
        // with the global Cmd-Tab-style switcher. Free users still see the
        // tooltip; the popover just never opens.
        guard ProductService.shared.isUnlocked(.windowSwitcher) else {
            dismiss()
            return false
        }

        if presentedSourceTileID == sourceTileID, !windows.isEmpty {
            return true
        }

        var seen = Set<String>()
        var aggregated: [AppWindow] = []
        let registry = WindowRegistry.shared
        let includesMinimized = DockyPreferences.shared.includesMinimizedWindows
        for bundleID in bundleIDs where !bundleID.isEmpty {
            for window in WorkspaceService.shared.appWindows(bundleIdentifier: bundleID) {
                // Minimized windows skip the strict capture check —
                // CGWindowServer often hides their bounds and we don't
                // need a live preview for them anyway. They're still
                // gated on the user preference and a valid cgWindowID
                // so AX entries for long-gone windows don't slip in.
                if window.isMinimized {
                    guard includesMinimized, window.cgWindowID != nil else { continue }
                } else {
                    guard registry.isCapturable(window) else { continue }
                }
                guard seen.insert(window.windowIdentifier).inserted else { continue }
                aggregated.append(window)
            }
        }

        guard !aggregated.isEmpty else {
            dismiss()
            return false
        }

        windows = aggregated
        windowPreviews = freezePreviews(for: aggregated)
        selectedWindowIdentifier = aggregated.first?.windowIdentifier
        presentedSourceTileID = sourceTileID
        presentedBundleIdentifier = bundleIDs.count == 1 ? bundleIDs.first : nil
        return true
    }

    func dismiss() {
        windows = []
        windowPreviews = [:]
        selectedWindowIdentifier = nil
        presentedSourceTileID = nil
        presentedBundleIdentifier = nil
        isContextMenuPresented = false
    }

    func confirm(window: AppWindow) {
        _ = WorkspaceService.shared.focus(window: window)
        dismiss()
    }

    func selectWindow(withIdentifier identifier: String) {
        guard windows.contains(where: { $0.windowIdentifier == identifier }) else { return }
        selectedWindowIdentifier = identifier
    }

    func setContextMenuPresented(_ presented: Bool) {
        isContextMenuPresented = presented
    }

    func windowPreview(for window: AppWindow) -> NSImage? {
        windowPreviews[window.windowIdentifier]
    }

    func removeWindow(withIdentifier identifier: String) {
        guard let index = windows.firstIndex(where: { $0.windowIdentifier == identifier }) else { return }
        windows.remove(at: index)
        windowPreviews.removeValue(forKey: identifier)

        if windows.isEmpty {
            // Route through the controller so the NSWindow is torn down too;
            // calling self.dismiss() alone would leave an invisible empty
            // floating window behind.
            WindowPreviewWindowController.shared.dismissCurrent()
            return
        }

        if selectedWindowIdentifier == identifier {
            let nextIndex = min(index, windows.count - 1)
            selectedWindowIdentifier = windows[nextIndex].windowIdentifier
        }
    }

    private func freezePreviews(for windows: [AppWindow]) -> [String: NSImage] {
        var result: [String: NSImage] = [:]
        for window in windows {
            if let preview = WorkspaceService.shared.appWindowPreview(for: window) {
                result[window.windowIdentifier] = preview
            }
        }
        return result
    }
}
