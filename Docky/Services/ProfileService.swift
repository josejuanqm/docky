//
//  ProfileService.swift
//  Docky
//
//  Owns the list of dock profiles and which one is active. Each profile
//  holds its own copy of the dock's tile-store fields (pinned items,
//  trailing items, widget placements, app widget displays, hidden-app
//  list). The active profile's data is mirrored into `DockyPreferences`'
//  legacy top-level keys so the rest of the app keeps working unchanged.
//
//  On first launch with this feature enabled, `migrateFromLegacyTileStore`
//  reads the existing top-level data straight off `DockyPreferences` and
//  wraps it in a "Default" profile. Subsequent launches load profiles
//  from `Keys.profiles` and skip migration.
//

import Foundation
import Observation

@Observable
final class ProfileService {
    static let shared = ProfileService()

    /// All known profiles, in user-defined order.
    private(set) var profiles: [DockProfile] = []

    /// Identifier of the currently-active profile. Mutations to the
    /// `DockyPreferences` tile-store fields are mirrored here.
    private(set) var activeProfileID: String = ""

    var activeProfile: DockProfile? {
        profiles.first(where: { $0.id == activeProfileID })
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let profiles = "docky.profiles"
        static let activeProfileID = "docky.activeProfileID"
    }

    private init() {
        if let data = defaults.data(forKey: Keys.profiles),
           let loaded = try? decoder.decode([DockProfile].self, from: data),
           !loaded.isEmpty {
            self.profiles = loaded
            let storedActive = defaults.string(forKey: Keys.activeProfileID) ?? ""
            self.activeProfileID = loaded.contains(where: { $0.id == storedActive })
                ? storedActive
                : loaded[0].id
        } else {
            migrateFromLegacyTileStore()
        }
    }

    private func migrateFromLegacyTileStore() {
        let prefs = DockyPreferences.shared
        let initial = DockProfile(
            name: "Default",
            symbolName: "house.fill",
            pinnedItems: prefs.pinnedItems,
            trailingItems: prefs.trailingItems,
            widgetPlacements: prefs.widgetPlacements,
            appWidgetDisplays: prefs.appWidgetDisplays,
            hiddenAppBundleIdentifiers: prefs.hiddenAppBundleIdentifiers
        )
        self.profiles = [initial]
        self.activeProfileID = initial.id
        persist()
    }

    func setActiveProfile(id: String) {
        guard activeProfileID != id,
              let profile = profiles.first(where: { $0.id == id })
        else { return }
        activeProfileID = id
        defaults.set(id, forKey: Keys.activeProfileID)
        DockyPreferences.shared.applyProfile(profile)
    }

    /// Apply a mutation to the active profile and persist. Used by
    /// `DockyPreferences` to mirror tile-store edits into the profile.
    func updateActiveProfile(_ mutate: (inout DockProfile) -> Void) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        mutate(&profiles[idx])
        persist()
    }

    @discardableResult
    func createProfile(
        name: String,
        symbolName: String = "circle.grid.3x3.fill",
        basedOn: DockProfile? = nil
    ) -> DockProfile {
        let profile = DockProfile(
            name: name,
            symbolName: symbolName,
            pinnedItems: basedOn?.pinnedItems ?? [],
            trailingItems: basedOn?.trailingItems ?? [],
            widgetPlacements: basedOn?.widgetPlacements ?? [],
            appWidgetDisplays: basedOn?.appWidgetDisplays ?? [],
            hiddenAppBundleIdentifiers: basedOn?.hiddenAppBundleIdentifiers ?? []
        )
        profiles.append(profile)
        persist()
        return profile
    }

    func renameProfile(id: String, to newName: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = newName
        persist()
    }

    func updateProfileSymbol(id: String, symbolName: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].symbolName = symbolName
        persist()
    }

    func addTrigger(_ trigger: ProfileTrigger, to profileID: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[idx].triggers.append(trigger)
        persist()
    }

    func updateTrigger(_ trigger: ProfileTrigger, in profileID: String) {
        guard let pIdx = profiles.firstIndex(where: { $0.id == profileID }),
              let tIdx = profiles[pIdx].triggers.firstIndex(where: { $0.id == trigger.id })
        else { return }
        profiles[pIdx].triggers[tIdx] = trigger
        persist()
    }

    func removeTrigger(_ triggerID: String, from profileID: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[idx].triggers.removeAll { $0.id == triggerID }
        persist()
    }

    func deleteProfile(id: String) {
        guard profiles.count > 1 else { return }
        let wasActive = activeProfileID == id
        profiles.removeAll { $0.id == id }
        if wasActive, let first = profiles.first {
            setActiveProfile(id: first.id)
        } else {
            persist()
        }
    }

    private func persist() {
        if let data = try? encoder.encode(profiles) {
            defaults.set(data, forKey: Keys.profiles)
        }
        defaults.set(activeProfileID, forKey: Keys.activeProfileID)
    }
}
