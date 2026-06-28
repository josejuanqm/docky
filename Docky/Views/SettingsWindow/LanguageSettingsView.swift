//
//  LanguageSettingsView.swift
//  Docky
//

import SwiftUI
import AppKit

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
    static let appleLanguagesKey = "AppleLanguages"

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
        guard let languages = defaults.array(forKey: appleLanguagesKey) as? [String],
              let first = languages.first, !first.isEmpty else {
            return .system
        }
        return .language(code: first)
    }

    /// Persists the selection. `.system` clears the override so macOS decides.
    static func apply(_ selection: DisplayLanguage, defaults: UserDefaults = .standard) {
        switch selection {
        case .system:
            defaults.removeObject(forKey: appleLanguagesKey)
        case .language(let code):
            defaults.set([code], forKey: appleLanguagesKey)
        }
    }
}

struct LanguageSettingsView: View {
    @State private var selection: DisplayLanguage
    @State private var showRelaunchPrompt = false

    init() {
        _selection = State(initialValue: LanguageController.currentSelection())
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: $selection) {
                    Text("Use System Language").tag(DisplayLanguage.system)
                    ForEach(LanguageController.availableCodes(), id: \.self) { code in
                        Text(LanguageController.displayName(for: code))
                            .tag(DisplayLanguage.language(code: code))
                    }
                } label: {
                    Text("Language")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Display Language")
            } footer: {
                Text("Docky must be relaunched to apply a language change.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onChange(of: selection) { _, newValue in
            LanguageController.apply(newValue)
            showRelaunchPrompt = true
        }
        .alert("Relaunch Docky?", isPresented: $showRelaunchPrompt) {
            Button("Relaunch Now") { relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Your language change takes effect after Docky restarts.")
        }
    }

    /// Reopens the app bundle, then terminates the current instance so the
    /// fresh process picks up the new `AppleLanguages` value.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}
