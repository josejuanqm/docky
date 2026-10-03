//
//  LanguageSettingsView.swift
//  Docky
//
//  Picks the language Docky renders in. `.system` hands control back to the
//  macOS language preference; anything else is a Docky-only choice.
//
//  Laid out with `Form` like every other settings pane. That is not cosmetic:
//  a plain `VStack` reports its full height as its ideal size, which
//  `NavigationSplitView` hands to the hosting controller, which grows the
//  window to match and then keeps re-applying it — the window becomes taller
//  than the screen and stops being resizable. A `Form` scrolls, so its ideal
//  height stays bounded and the window keeps behaving like a window.
//

import SwiftUI

struct LanguageSettingsView: View {
    @State private var selection: AppLanguage = LanguageManager.shared.selected

    private var isPending: Bool { selection != LanguageManager.shared.selected }

    var body: some View {
        Form {
            Section {
                Text(L10n.text(
                    "Pick the language Docky runs in. Choosing anything other than Follow System keeps Docky in that language even after you change the macOS language. Docky restarts so the menu bar switches along with the rest of the interface."
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Language") {
                Picker("Language", selection: $selection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(label(for: language)).tag(language)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            if isPending {
                Section {
                    HStack {
                        Text(L10n.text("Docky will restart to apply this change."))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Button(L10n.text("Restart Now")) { restart() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: selection) { _ in
            restart()
        }
    }

    private func label(for language: AppLanguage) -> String {
        language == .system ? L10n.text("Follow System") : L10n.text(language.endonym)
    }

    private func restart() {
        guard isPending else { return }
        LanguageManager.shared.selected = selection
        LanguageManager.shared.relaunchAfterChange()
    }
}
