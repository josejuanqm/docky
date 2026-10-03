//
//  HiddenAppsSettingsView.swift
//  Docky
//

import AppKit
import SwiftUI

struct HiddenAppsSettingsView: View {
    @Bindable private var preferences = DockyPreferences.shared

    var body: some View {
        Form {
            Section("Restore") {
                Text("Apps hidden with \"Hide in Docky\" stay out of Docky's pinned and running app surfaces until you restore them here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if hiddenApps.isEmpty {
                    Text("No apps are currently hidden from Docky.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hiddenApps) { app in
                        HiddenAppRow(app: app)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hiddenApps: [HiddenAppSettingsEntry] {
        let dockyBundleID = Bundle.main.bundleIdentifier
        return preferences.hiddenAppBundleIdentifiers
            .filter { $0 != dockyBundleID }
            .compactMap { bundleIdentifier in
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            let displayName = appURL.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleIdentifier
            let subtitle = appURL == nil
                ? "\(bundleIdentifier) • App not currently found on disk"
                : bundleIdentifier

            return HiddenAppSettingsEntry(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                subtitle: subtitle,
                icon: IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
            )
        }
        .sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier.localizedCaseInsensitiveCompare(rhs.bundleIdentifier) == .orderedAscending
            }
            return comparison == .orderedAscending
        }
    }
}

private struct HiddenAppRow: View {
    let app: HiddenAppSettingsEntry

    @Bindable private var preferences = DockyPreferences.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.headline)

                Text(L10n.text(app.subtitle))
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Show in Docky") {
                preferences.setAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier, isHidden: false)
            }
        }
    }
}

private struct HiddenAppSettingsEntry: Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let subtitle: String
    let icon: NSImage

    var id: String { bundleIdentifier }
}
