//
//  LanguageControllerTests.swift
//  DockyTests
//
//  Pure-logic tests for the display-language override. No app host needed:
//  LanguageController.swift is compiled directly into this test target.
//

import Testing
import Foundation

struct LanguageControllerTests {
    /// A throwaway defaults domain so tests never touch the real app prefs.
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func systemSelectionWhenNothingStored() {
        let defaults = makeDefaults("LangTest.system")
        #expect(LanguageController.currentSelection(defaults: defaults) == .system)
    }

    @Test func applyLanguageStoresBothKeys() {
        let defaults = makeDefaults("LangTest.apply")
        LanguageController.apply(.language(code: "ja"), defaults: defaults)
        // Docky's own key is the source of truth for the picker...
        #expect(defaults.string(forKey: LanguageController.preferenceKey) == "ja")
        // ...and AppleLanguages is written for macOS to honor on next launch.
        #expect(defaults.array(forKey: LanguageController.appleLanguagesKey) as? [String] == ["ja"])
        #expect(LanguageController.currentSelection(defaults: defaults) == .language(code: "ja"))
    }

    @Test func applySystemClearsOverride() {
        let defaults = makeDefaults("LangTest.clear")
        LanguageController.apply(.language(code: "es"), defaults: defaults)
        LanguageController.apply(.system, defaults: defaults)
        // Assert via Docky's own key: AppleLanguages lives in the global domain
        // and falls back to the system value, so it can't be checked for nil here.
        #expect(defaults.string(forKey: LanguageController.preferenceKey) == nil)
        #expect(LanguageController.currentSelection(defaults: defaults) == .system)
    }

    @Test func displayNamesAreAutonyms() {
        #expect(LanguageController.displayName(for: "ja") == "日本語")
        #expect(LanguageController.displayName(for: "en") == "English")
    }

    @Test func displayNameIsCapitalized() {
        // Spanish autonym is lowercase ("español"); we capitalize the first letter.
        #expect(LanguageController.displayName(for: "es").first == "E")
    }

    @Test func availableCodesExcludeBase() {
        #expect(!LanguageController.availableCodes().contains("Base"))
    }
}
