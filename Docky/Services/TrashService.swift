//
//  TrashService.swift
//  Docky
//

import AppKit
import Combine
import Dispatch
import Foundation

final class TrashService: ObservableObject {
    static let shared = TrashService()

    @Published private(set) var isEmpty = true

    private let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
    private var trashFileDescriptor: CInt = -1
    private var trashSource: DispatchSourceFileSystemObject?

    private init() {
        refresh()
        startWatchingTrashDirectory()
    }

    deinit {
        trashSource?.cancel()
        if trashFileDescriptor >= 0 {
            close(trashFileDescriptor)
        }
    }

    func refresh() {
        let fileManager = FileManager.default
        let contents = try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        isEmpty = contents?.isEmpty != false
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
            self?.refresh()
        }

        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        trashSource = source
        source.resume()
    }
}
