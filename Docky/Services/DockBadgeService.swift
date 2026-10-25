//
//  DockBadgeService.swift
//  Docky
//
//  Reads notification badges (the red number on Mail, Messages, etc.) for
//  running apps and republishes them keyed by bundle identifier so tiles can
//  draw their own badge.
//
//  Source of truth: LaunchServices. The system Dock's accessibility tree has
//  the badge too, but Docky restarts the Dock to hide it, and the new Dock
//  shows no badge until the app sets it again.
//

import AppKit
import Combine

@MainActor
final class DockBadgeService: ObservableObject {
    static let shared = DockBadgeService()

    /// Badge text per bundle identifier, e.g. ["com.apple.mail": "5"].
    /// Apps with no badge are absent from the map.
    @Published private(set) var badgesByBundleID: [String: String] = [:]

    /// Nothing notifies us of badge changes, so we poll. Each read is one
    /// LaunchServices lookup per running app.
    private let pollInterval: TimeInterval = 2

    private var timer: Timer?

    private init() {}

    func badge(forBundleIdentifier bundleIdentifier: String) -> String? {
        badgesByBundleID[bundleIdentifier]
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private func refresh() {
        var newBadges: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier,
                  let badge = badgeLabel(forProcessIdentifier: app.processIdentifier) else { continue }
            newBadges[bundleID] = badge
        }

        if newBadges != badgesByBundleID {
            badgesByBundleID = newBadges
        }
    }

    /// The badge string the app set (e.g. "5", "•"). Empty / whitespace
    /// means no badge.
    private func badgeLabel(forProcessIdentifier pid: pid_t) -> String? {
        guard let asn = _LSASNCreateWithPid(nil, pid)?.takeRetainedValue(),
              let info = _LSCopyApplicationInformationItem(kLSDefaultSessionID, asn, "StatusLabel" as CFString)?
                .takeRetainedValue() as? [String: Any],
              let label = info["label"] as? String else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
