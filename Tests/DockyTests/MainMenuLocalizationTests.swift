//
//  MainMenuLocalizationTests.swift
//  DockyTests
//
//  The AppKit main menu is localized via .lproj/MainMenu.strings (separate from
//  the String Catalog). This checks the Japanese strings file has parity with
//  the Spanish one — every menu item the project translates should be covered.
//

import Testing
import Foundation

struct MainMenuLocalizationTests {
    private static var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Parses the "<ObjectID>.title" keys out of a .strings file.
    private func keys(of lproj: String) -> Set<String> {
        let url = Self.repoRoot.appending(path: "Docky/\(lproj)/MainMenu.strings")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var result = Set<String>()
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("\"") , let eq = line.firstIndex(of: "=") else { continue }
            let lhs = line[..<eq].trimmingCharacters(in: .whitespaces)
            if lhs.hasPrefix("\"") {
                result.insert(lhs.replacingOccurrences(of: "\"", with: ""))
            }
        }
        return result
    }

    @Test func japaneseMainMenuMatchesSpanishCoverage() {
        let es = keys(of: "es.lproj")
        let ja = keys(of: "ja.lproj")
        #expect(!ja.isEmpty, "ja MainMenu.strings produced no entries")
        let missing = es.subtracting(ja)
        #expect(missing.isEmpty, "ja MainMenu.strings is missing keys present in es: \(missing.prefix(20))")
    }

    @Test func japaneseMainMenuHasNoSpanishLeftovers() {
        let url = Self.repoRoot.appending(path: "Docky/ja.lproj/MainMenu.strings")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Sentinel Spanish words that must not appear in translated values.
        for spanish in ["Mostrar", "Ventana", "Archivo", "Cerrar", "Ayuda"] {
            #expect(!text.contains("= \"\(spanish)"), "Found untranslated Spanish value: \(spanish)")
        }
    }
}
