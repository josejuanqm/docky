//
//  RecentFilesService.swift
//  Docky
//
//  Live "Recents" list backed by Spotlight, mirroring Finder's sidebar
//  Recents canned search at:
//    /System/Library/CoreServices/Finder.app/Contents/Resources/
//      MyLibraries/myDocuments.cannedSearch/Resources/search.savedSearch
//
//  The predicate filters to files that have a kMDItemLastUsedDate set and
//  whose UTI tree is user-perceivable content (or Office docs, or archives).
//  Results stream in live; consumers observe `recentURLs`.
//

import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class RecentFilesService: ObservableObject {
    static let shared = RecentFilesService()
    private static let logger = Logger(subsystem: "gt.quintero.Docky", category: "RecentFiles")

    @Published private(set) var recentURLs: [URL] = []

    private let query: NSMetadataQuery
    private var observers: [NSObjectProtocol] = []
    private static let maxResults = 50

    private init() {
        let query = NSMetadataQuery()
        query.operationQueue = .main
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        // `kMDItemLastUsedDate > epoch` is the NSPredicate-friendly way to
        // express MDQuery's `kMDItemLastUsedDate = "*"` (has any value).
        // `LIKE` is string-only in NSPredicate and silently matches nothing
        // against a date attribute.
        let oldDate = Date(timeIntervalSince1970: 0) as NSDate
        query.predicate = NSPredicate(
            format: "kMDItemLastUsedDate > %@ AND (kMDItemContentTypeTree == %@ OR kMDItemContentTypeTree LIKE[cd] %@ OR kMDItemContentTypeTree == %@)",
            oldDate,
            "public.content",
            "com.microsoft.*",
            "public.archive"
        )
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        query.notificationBatchingInterval = 1.0
        self.query = query

        Self.logger.info("init predicate=\(query.predicate?.predicateFormat ?? "nil", privacy: .public)")

        let center = NotificationCenter.default
        for name in [
            NSNotification.Name.NSMetadataQueryDidStartGathering,
            .NSMetadataQueryGatheringProgress,
            .NSMetadataQueryDidFinishGathering,
            .NSMetadataQueryDidUpdate
        ] {
            let capturedName = name
            let token = center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleNotification(named: capturedName)
                }
            }
            observers.append(token)
        }

        let started = query.start()
        Self.logger.info("query.start() returned=\(started, privacy: .public)")
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        query.stop()
    }

    private func handleNotification(named name: NSNotification.Name) {
        Self.logger.info("notification name=\(name.rawValue, privacy: .public) resultCount=\(self.query.resultCount, privacy: .public) isGathering=\(self.query.isGathering, privacy: .public)")
        refresh()
    }

    private func refresh() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let count = min(query.resultCount, Self.maxResults)
        var urls: [URL] = []
        urls.reserveCapacity(count)
        var loggedFirst = false
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem else {
                if !loggedFirst {
                    Self.logger.error("result at index 0 was not NSMetadataItem")
                    loggedFirst = true
                }
                continue
            }
            let url = url(from: item)
            if !loggedFirst {
                let urlValueType = String(describing: type(of: item.value(forAttribute: NSMetadataItemURLKey) ?? "nil"))
                let pathValueType = String(describing: type(of: item.value(forAttribute: NSMetadataItemPathKey) ?? "nil"))
                Self.logger.info("first result urlKeyType=\(urlValueType, privacy: .public) pathKeyType=\(pathValueType, privacy: .public) extractedURL=\(url?.lastPathComponent ?? "nil", privacy: .public)")
                loggedFirst = true
            }
            if let url {
                urls.append(url)
            }
        }

        Self.logger.info("refresh built urls.count=\(urls.count, privacy: .public) fromResultCount=\(count, privacy: .public)")

        if urls != recentURLs {
            Self.logger.info("recentURLs updated count=\(urls.count, privacy: .public) first=\(urls.first?.lastPathComponent ?? "nil", privacy: .public)")
            recentURLs = urls
        }
    }

    private func url(from item: NSMetadataItem) -> URL? {
        if let value = item.value(forAttribute: NSMetadataItemURLKey) {
            if let url = value as? URL { return url }
            if let nsURL = value as? NSURL { return nsURL as URL }
        }
        if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
