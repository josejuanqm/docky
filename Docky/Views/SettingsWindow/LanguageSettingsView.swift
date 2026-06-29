//
//  LanguageSettingsView.swift
//  Docky
//

import SwiftUI
import AppKit

// `DisplayLanguage` and `LanguageController` live in LanguageController.swift
// so the selection/apply logic can be compiled into the test target without
// pulling in this SwiftUI view.

struct LanguageSettingsView: View {
    @State private var selection: DisplayLanguage
    @State private var showRelaunchPrompt = false

    init() {
        let current = LanguageController.currentSelection()
        let clamped = LanguageController.validated(current, available: LanguageController.availableCodes())
        _selection = State(initialValue: clamped)
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
