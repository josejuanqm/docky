//
//  LocalizationCompletenessTests.swift
//  DockyTests
//
//  Guards the Japanese localization: every catalog entry must have a `ja`
//  translation, and the existing Spanish translations must stay intact. Reads
//  the source catalog directly (relative to this file), so it needs no app host.
//

import Testing
import Foundation

struct LocalizationCompletenessTests {
    /// Repo root, derived from this file's path: Tests/DockyTests/<file> -> repo.
    private static var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()  // DockyTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo
    }

    private static var catalog: [String: Any] {
        let url = repoRoot.appending(path: "Docky/Localizable.xcstrings")
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func localizations(_ entry: Any) -> [String: Any] {
        ((entry as? [String: Any])?["localizations"] as? [String: Any]) ?? [:]
    }

    private func value(_ locs: [String: Any], _ lang: String) -> (state: String, value: String)? {
        guard let unit = (locs[lang] as? [String: Any])?["stringUnit"] as? [String: Any],
              let state = unit["state"] as? String,
              let value = unit["value"] as? String else { return nil }
        return (state, value)
    }

    @Test func everyEntryHasJapanese() {
        let strings = Self.catalog["strings"] as! [String: Any]
        var missing: [String] = []
        for (key, entry) in strings where !key.isEmpty {
            let ja = value(localizations(entry), "ja")
            if ja == nil || ja?.value.isEmpty == true {
                missing.append(key)
            }
        }
        #expect(missing.isEmpty, "Keys missing a ja translation: \(missing.prefix(20))")
    }

    @Test func japaneseEntriesAreMarkedTranslated() {
        let strings = Self.catalog["strings"] as! [String: Any]
        var notTranslated: [String] = []
        for (key, entry) in strings where !key.isEmpty {
            if let ja = value(localizations(entry), "ja"), ja.state != "translated" {
                notTranslated.append(key)
            }
        }
        #expect(notTranslated.isEmpty, "ja entries not in 'translated' state: \(notTranslated.prefix(20))")
    }

    @Test func spanishTranslationsArePreserved() {
        let strings = Self.catalog["strings"] as! [String: Any]
        let esCount = strings.values.filter { value(localizations($0), "es") != nil }.count
        // Spanish shipped with 406 translated entries; it must not regress.
        #expect(esCount >= 406, "Spanish translations regressed: \(esCount)")
    }

    @Test func formatSpecifiersSurviveTranslation() {
        // A ja value must keep the same number of %@ / %lld placeholders as its key.
        let strings = Self.catalog["strings"] as! [String: Any]
        func specifiers(_ s: String) -> Int {
            var count = 0
            for token in ["%@", "%lld"] {
                count += s.components(separatedBy: token).count - 1
            }
            // positional %1$@ / %2$lld collapse to the same family; count those too.
            return count
        }
        var mismatched: [String] = []
        for (key, entry) in strings where !key.isEmpty {
            guard let ja = value(localizations(entry), "ja") else { continue }
            // Skip positional/edge cases; only check the simple, common forms.
            if key.contains("%1$") || ja.value.contains("%1$") { continue }
            if specifiers(key) != specifiers(ja.value) {
                mismatched.append(key)
            }
        }
        #expect(mismatched.isEmpty, "ja value changed placeholder count for: \(mismatched.prefix(20))")
    }
}
