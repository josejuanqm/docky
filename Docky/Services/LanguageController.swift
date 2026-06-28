//
//  LanguageController.swift
//  Docky
//

import Foundation

/// A user-selectable UI language. `.system` follows the macOS preference,
/// `.language` pins Docky to a specific bundled localization.
enum DisplayLanguage: Hashable, Identifiable {
    case system
    case language(code: String)

    var id: String {
        switch self {
        case .system: "system"
        case .language(let code): code
        }
    }
}

/// Reads and writes the per-app language override. macOS reads `AppleLanguages`
/// from the app's user defaults at launch and loads the matching `.lproj`, so
/// writing it here is all that's needed — the change applies on the next start.
///
/// Kept free of UI so the selection/apply logic can be unit tested.
enum LanguageController {
    /// The key macOS reads at launch to pick the UI language.
    static let appleLanguagesKey = "AppleLanguages"
    /// Docky's own record of the user's choice. `AppleLanguages` lives in the
    /// global domain (every defaults suite inherits the system value), so it
    /// can't tell "user picked a language" from "inherited the system one".
    /// This dedicated key is the source of truth for the picker's selection.
    static let preferenceKey = "DockyPreferredLanguage"

    /// Language codes Docky actually ships, excluding the "Base" development
    /// pseudo-localization. Derived from the bundle so a newly added `.lproj`
    /// shows up in the picker without code changes.
    static func availableCodes(bundle: Bundle = .main) -> [String] {
        bundle.localizations
            .filter { $0 != "Base" }
            .sorted()
    }

    /// The language's name written in its own language (e.g. "日本語",
    /// "English", "Español"), matching how macOS lists languages.
    static func displayName(for code: String) -> String {
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).localizedUppercase + name.dropFirst()
    }

    /// The currently selected override, or `.system` when none is set.
    static func currentSelection(defaults: UserDefaults = .standard) -> DisplayLanguage {
        guard let code = defaults.string(forKey: preferenceKey),
              code != "system", !code.isEmpty else {
            return .system
        }
        return .language(code: code)
    }

    /// Returns `selection` unchanged if it refers to a code present in
    /// `available`, or `.system` when the stored code is no longer shipped.
    /// Guards the picker's initial value against stale user-defaults entries
    /// (e.g. a language removed in a future build).
    static func validated(_ selection: DisplayLanguage, available: [String]) -> DisplayLanguage {
        if case .language(let code) = selection, !available.contains(code) {
            return .system
        }
        return selection
    }

    /// Persists the selection. `.system` clears the override so macOS decides.
    /// Writes both Docky's own key (for the picker) and `AppleLanguages` in the
    /// app domain (which macOS honors on the next launch).
    static func apply(_ selection: DisplayLanguage, defaults: UserDefaults = .standard) {
        switch selection {
        case .system:
            defaults.removeObject(forKey: preferenceKey)
            defaults.removeObject(forKey: appleLanguagesKey)
        case .language(let code):
            defaults.set(code, forKey: preferenceKey)
            defaults.set([code], forKey: appleLanguagesKey)
        }
    }
}
