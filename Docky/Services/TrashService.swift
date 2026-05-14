//
//  TrashService.swift
//  Docky
//

import AppKit
import Combine
import Dispatch
import Foundation

@MainActor
final class TrashService: ObservableObject {
    static let shared = TrashService()

    @Published private(set) var isEmpty = true
    /// `false` in the sandboxed (MAS) build until the user grants
    /// access via `requestAccess()`. Used by the trash tile to swap
    /// in a "needs permission" affordance instead of always-empty.
    @Published private(set) var hasAccess = true

    private let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
    private var trashFileDescriptor: CInt = -1
    private var trashSource: DispatchSourceFileSystemObject?

    private init() {
        #if APP_STORE_SANDBOX
        // Sandbox: only proceed if we already have a bookmark.
        hasAccess = BookmarkedURLStore.shared.hasBookmark(for: .trash)
        if hasAccess {
            refresh()
            startWatchingTrashDirectory()
        }
        #else
        refresh()
        startWatchingTrashDirectory()
        #endif
    }

    deinit {
        trashSource?.cancel()
        if trashFileDescriptor >= 0 {
            close(trashFileDescriptor)
        }
    }

    /// Prompts the user to pick `~/.Trash` so the sandboxed build
    /// can establish a security-scoped bookmark to it. Pre-fills the
    /// open panel's directory so it's a one-click confirmation.
    /// No-op on Dev ID builds (trash access is unconditional there).
    func requestAccess() {
        #if APP_STORE_SANDBOX
        let panel = NSOpenPanel()
        panel.directoryURL = trashURL
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.title = "Pick your Trash folder"
        panel.message = "Docky needs access to your Trash to show its contents in the dock. Confirm the pre-selected ~/.Trash folder."
        panel.prompt = "Grant Access"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BookmarkedURLStore.shared.store(url: url, for: .trash)
            hasAccess = true
            refresh()
            startWatchingTrashDirectory()
        } catch {
            NSLog("[Docky] Failed to store trash bookmark: \(error.localizedDescription)")
        }
        #endif
    }

    func refresh() {
        #if APP_STORE_SANDBOX
        guard hasAccess else {
            isEmpty = true
            return
        }
        do {
            try BookmarkedURLStore.shared.withResolvedURL(for: .trash) { resolved in
                let contents = try? FileManager.default.contentsOfDirectory(
                    at: resolved,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                isEmpty = contents?.isEmpty != false
            }
        } catch {
            // Bookmark is broken; flip back to "needs permission".
            hasAccess = false
            isEmpty = true
        }
        #else
        let fileManager = FileManager.default
        let contents = try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        isEmpty = contents?.isEmpty != false
        #endif
    }

    private func startWatchingTrashDirectory() {
        let descriptor = open(trashURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        trashFileDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }

        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        trashSource = source
        source.resume()
    }
}
