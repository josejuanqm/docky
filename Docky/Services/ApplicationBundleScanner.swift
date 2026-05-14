//
//  ApplicationBundleScanner.swift
//  Docky
//
//  Sandbox-safe replacement for `FileManager.contentsOfDirectory()`
//  scans of `/Applications`, `/System/Applications`, `~/Applications`,
//  and their immediate subfolders.
//
//  Uses `NSMetadataQuery` (Spotlight) which:
//    - Works in the App Store sandbox (no file-read entitlements
//      needed for the actual scan).
//    - Returns indexed apps wherever they live on disk (covers the
//      three "Applications" roots and any user-installed bundle
//      under `~/Applications`, `/opt/`, mounted volumes, etc.).
//    - Stays in sync as apps are installed / removed.
//
//  Two flavors of consumer:
//    - One-shot snapshots (settings panes that show a list once):
//      use `discoverInstalled(completion:)` which fires the query,
//      delivers the result, then disposes itself.
//    - Live observers (Launchpad grid, App Folders palette) that
//      want updates when apps come and go: subscribe to
//      `installedApps`, the shared scanner keeps a single live
//      query going for the whole app lifecycle.
//

import AppKit
import Combine
import Foundation

struct DiscoveredApplication: Equatable, Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String
    let url: URL
    /// `/Applications`, `/System/Applications`, `~/Applications`, or
    /// the enclosing folder (e.g. `/Applications/Utilities`). Used by
    /// the launchpad grid to group entries by their containing folder.
    let containingDirectory: URL?

    var id: String { bundleIdentifier }
}

@MainActor
final class ApplicationBundleScanner: ObservableObject {
    static let shared = ApplicationBundleScanner()

    /// Live, de-duplicated list of every indexed `.app` bundle on
    /// the system. Empty until the first query gathering phase
    /// completes. Updates as apps are installed / removed.
    @Published private(set) var installedApps: [DiscoveredApplication] = []

    private let query: NSMetadataQuery
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        query.searchScopes = [
            NSMetadataQueryLocalComputerScope,
            NSMetadataQueryUserHomeScope
        ]
        query.notificationBatchingInterval = 0.5
        self.query = query

        // Both notifications shape the same `installedApps` array;
        // gathering fires once after startup, updates fire whenever
        // Spotlight notices an install/uninstall.
        NotificationCenter.default
            .publisher(for: .NSMetadataQueryDidFinishGathering, object: query)
            .merge(with: NotificationCenter.default.publisher(for: .NSMetadataQueryDidUpdate, object: query))
            .sink { [weak self] _ in
                self?.collectResults()
            }
            .store(in: &cancellables)
    }

    /// Kicks off the live query. Idempotent. Call from app launch so
    /// `installedApps` is populated before any settings pane that
    /// reads it appears.
    func startIfNeeded() {
        guard !query.isStarted else { return }
        query.start()
    }

    /// One-shot snapshot for callers that don't want a long-lived
    /// observer. Internally piggybacks on the shared live query:
    /// returns immediately if results are already in, otherwise
    /// waits for the next gathering completion.
    func discoverInstalled(completion: @escaping ([DiscoveredApplication]) -> Void) {
        startIfNeeded()
        if !installedApps.isEmpty {
            completion(installedApps)
            return
        }
        // First-call path: wait for the gathering notification once.
        var token: AnyCancellable?
        token = $installedApps
            .filter { !$0.isEmpty }
            .first()
            .sink { apps in
                completion(apps)
                _ = token  // keep alive until fire
                token = nil
            }
    }

    private func collectResults() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var seen: Set<String> = []
        var apps: [DiscoveredApplication] = []
        apps.reserveCapacity(query.resultCount)

        for raw in query.results {
            guard let item = raw as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }
            let url = URL(fileURLWithPath: path)

            // De-dupe by bundle id. If Spotlight indexed the same
            // app under two paths (e.g. an old copy in Trash that
            // got re-indexed, or a TimeMachine snapshot), prefer
            // whichever we saw first.
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  !seen.contains(bundleID) else {
                continue
            }
            seen.insert(bundleID)

            let displayName = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent

            apps.append(DiscoveredApplication(
                bundleIdentifier: bundleID,
                displayName: displayName,
                url: url,
                containingDirectory: url.deletingLastPathComponent()
            ))
        }

        apps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if apps != installedApps {
            installedApps = apps
        }
    }
}
