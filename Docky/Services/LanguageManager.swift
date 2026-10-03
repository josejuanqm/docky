//
//  LanguageManager.swift
//  Docky
//
//  Lets the user pick Docky's language inside the app instead of following the
//  system-wide macOS language.
//
//  How it works
//  ------------
//  SwiftUI resolves `Text("some literal")` through
//  `Bundle.main.localizedString(forKey:value:table:)`, as do `NSAlert`,
//  `NSMenuItem`, `.help()`, `.navigationTitle()` and friends. Overriding that
//  single method therefore covers every surface at once — including the ones
//  that take a plain `String` and would otherwise never be translated.
//
//  The override resolves keys against `Contents/Resources/<region>.lproj/*.strings`,
//  which is where Xcode compiles `Localizable.xcstrings` and `MainMenu.strings`.
//  Anything the override can't find falls through to Foundation's real
//  implementation, so the behaviour is unchanged whenever no override is active
//  (the "Follow System" case) or a key has no translation yet.
//
//  Menu-bar titles coming from `MainMenu.xib` are frozen when the nib loads,
//  which happens before this app's delegate runs. Changing language therefore
//  restarts Docky; see `relaunchAfterChange()`.

import AppKit
import Foundation
import ObjectiveC

// MARK: - AppLanguage

/// Every language Docky can render in.
///
/// `.system` hands control back to the macOS language preference; every other
/// case is selected inside the app and outlives a language change of the OS.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case en = "en"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case zhHK = "zh-HK"
    case fr = "fr"
    case es = "es"

    var id: String { rawValue }

    /// Bundle region whose `.lproj` directory holds the strings for this language.
    var region: String {
        switch self {
        case .system: "Base"
        case .en: "en"
        case .zhHans: "zh-Hans"
        case .zhHant: "zh-Hant"
        case .zhHK: "zh-HK"
        case .fr: "fr"
        case .es: "es"
        }
    }

    /// The language's own name, so the picker stays readable in every locale.
    ///
    /// Passed through `L10n.text(_:)` — the endonyms live in the string catalog
    /// so they can be shown in Japanese or any other language Docky learns later.
    var endonym: String {
        switch self {
        case .system: ""
        case .en: "English"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文（台灣）"
        case .zhHK: "繁體中文（香港）"
        case .fr: "Français"
        case .es: "Español"
        }
    }
}

// MARK: - LanguageManager

/// Owns the in-app language choice and installs the `Bundle.main` override.
final class LanguageManager {
    static let shared = LanguageManager()

    private static let storageKey = "preferredAppLanguage"

    private let defaults: UserDefaults

    private var tableCache: [String: [String: String]] = [:]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.storageKey) == nil {
            defaults.set(AppLanguage.system.rawValue, forKey: Self.storageKey)
        }
    }

    // MARK: Selection

    var selected: AppLanguage {
        get {
            AppLanguage(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
        }
    }

    /// `nil` means "let macOS decide" — the override then stays out of the way.
    var overrideRegion: String? {
        selected == .system ? nil : selected.region
    }

    // MARK: Override

    private var overrideInstalled = false

    /// Replaces `Bundle.main.localizedString(forKey:value:table:)` with one that
    /// consults the selected language first. Safe to call more than once.
    ///
    /// Must run on the main thread. Call it at the top of
    /// `applicationDidFinishLaunching` so no string is resolved before it.
    func installOverride() {
        // Runs on every launch, not just the first override: the per-app
        // language list is the source of truth for the main menu and can be
        // reset outside the app (a defaults write, a restore from backup).
        applyToPerAppLanguageList()

        guard !overrideInstalled else { return }
        guard let method = class_getInstanceMethod(
            Bundle.self,
            #selector(Bundle.localizedString(forKey:value:table:))
        ) else { return }

        typealias OriginalIMP = @convention(c) (Bundle, Selector, String, String?, String?) -> String
        let original = unsafeBitCast(method_getImplementation(method), to: OriginalIMP.self)

        let selector = #selector(Bundle.localizedString(forKey:value:table:))
        let block: @convention(block) (Bundle, String, String?, String?) -> String = { bundle, key, value, table in
            if let hit = LanguageManager.shared.localized(key: key, value: value, table: table) {
                return hit
            }
            return original(bundle, selector, key, value, table)
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
        overrideInstalled = true
    }

    /// Resolves `key` against the selected language's `.strings` tables.
    /// Returns `nil` when the language follows the system or the key is absent,
    /// which hands the decision back to Foundation's own lookup.
    func localized(key: String, value: String?, table: String?) -> String? {
        guard let region = overrideRegion else { return nil }
        let name = table ?? "Localizable"

        guard let table = stringsTable(named: name, region: region) else { return nil }
        if let hit = table[key], !hit.isEmpty { return hit }

        // `Localizable.strings` lives in every region; for nib-driven tables such
        // as MainMenu fall back to the region's directory only.
        return nil
    }

    /// Every region Docky ships a `MainMenu.strings` for. The English table is
    /// not a localization — it carries the nib's own titles, which
    /// `Base.lproj/MainMenu.nib` cannot expose at runtime.
    private static let mainMenuRegions = ["en", "es", "fr", "zh-Hans", "zh-Hant", "zh-HK"]

    private func stringsTable(named name: String, region: String) -> [String: String]? {
        let cacheKey = "\(region)/\(name)"
        if let cached = tableCache[cacheKey] { return cached }

        let url = resourcesURL
            .appendingPathComponent("\(region).lproj")
            .appendingPathComponent("\(name).strings")

        let plist = NSDictionary(contentsOf: url) as? [String: String]

        // Two on-disk formats come out of the toolchain. `Localizable.strings`
        // is a property list — UTF-16 XML, which Foundation decodes but
        // `String(contentsOf:encoding:)` cannot read. `MainMenu.strings` stays
        // the plain `"key" = "value";` text format. Try the plist first and
        // fall back to the text parser so both survive.
        let table: [String: String]
        if let plist, !plist.isEmpty {
            table = plist
        } else if let raw = try? String(contentsOf: url, encoding: .utf8) {
            table = Self.parseStrings(raw)
        } else {
            table = [:]
        }

        tableCache[cacheKey] = table
        return table
    }

    private var resourcesURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents").appendingPathComponent("Resources")
    }

    // MARK: Restart

    /// The main menu is built from a nib that is already loaded by the time this
    /// app runs, so a language change only lands cleanly on a fresh launch.
    func relaunchAfterChange() {
        let bundlePath = Bundle.main.bundlePath
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try? NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: bundlePath),
                configuration: configuration
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Re-titles the live main menu when the chosen language is not the one the
    /// nib already loaded in.
    ///
    /// `MainMenu.xib` is loaded by `NSApplicationMain` before any Swift in this
    /// app runs, so the per-app `AppleLanguages` list is the only thing that can
    /// influence it — and macOS ignores an app that writes that key while it is
    /// running. The nib's titles are therefore whatever the macOS language is,
    /// and this walk swaps them. The ObjectIDs line every `MainMenu.strings`
    /// table up, so a title-to-title map is enough — no nib surgery, no private
    /// API. Call before `configureMainMenu()`, which looks items up by title.
    func localizeMainMenu() {
        guard let target = overrideRegion else {
            return
        }
        guard let menu = NSApp.mainMenu else {
            return
        }
        let titles = mainMenuTitleMap(to: target)

        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let localized = titles[item.title] { item.title = localized }
                if let submenu = item.submenu { walk(submenu) }
            }
        }
        walk(menu)
    }

    /// Builds a "title as the nib spelled it" → "title in `target`" table.
    ///
    /// There is no way to ask which language the nib settled on, and it is not
    /// worth guessing from `preferredLocalizations`: writing `AppleLanguages`
    /// updates that list inside the running process, so it already reports the
    /// target by the time this runs. Every shipped language is therefore treated
    /// as a possible source. ObjectIDs keep the result unambiguous — two entries
    /// that share a title in one language share it in all of them.
    private func mainMenuTitleMap(to target: String) -> [String: String] {
        guard let targetTable = stringsTable(named: "MainMenu", region: target) else { return [:] }

        var titles: [String: String] = [:]
        for region in Self.mainMenuRegions where region != target {
            guard let table = stringsTable(named: "MainMenu", region: region) else { continue }
            for (objectID, title) in table {
                guard let translated = targetTable[objectID] else { continue }
                titles[title] = translated
            }
        }
        return titles
    }

    // MARK: Per-app language list

    /// Mirrors the choice into this app's `AppleLanguages` preference.
    ///
    /// This is the part that actually governs the **main menu**. `MainMenu.xib`
    /// is loaded by `NSApplicationMain` before any Swift in this app runs, so
    /// the `Bundle.main` override below cannot reach it — the nib picks its
    /// language from the app's own `AppleLanguages` list at load time. Writing
    /// it there is what makes the menu bar change language too, and it takes
    /// effect on the next launch, which is why a switch restarts Docky.
    ///
    /// "Follow System" removes the key so the macOS preference applies again.
    func applyToPerAppLanguageList() {
        let key = "AppleLanguages"
        guard selected != .system else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        // Only the chosen language goes in. macOS seeds this key with the
        // system language while the app runs, and those region codes carry a
        // script suffix (`zh-Hans-CN`) that matches no `.lproj` on disk —
        // appending them makes the whole list fail to resolve and Docky falls
        // back to the system language even though the right entry is first.
        UserDefaults.standard.set([selected.region], forKey: key)
    }

    // MARK: Parsing

    /// Reads `"key" = "value";` pairs out of a `.strings` file.
    ///
    /// Comments are ignored; only the `key = value` lines matter, and escapes
    /// such as `\"` and `\n` are resolved the way `genstrings` writes them.
    private static func parseStrings(_ raw: String) -> [String: String] {
        var table: [String: String] = [:]
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            // An entry line is `"key" = "value";`. Splitting on the single `=`
            // avoids a regex whose escape layer is impossible to keep honest,
            // and the quotes around both halves reject comment lines.
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasSuffix(";"), let equals = line.firstIndex(of: "=") else { continue }

            let lhs = line[..<equals].trimmingCharacters(in: .whitespaces)
            var rhs = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if rhs.hasSuffix(";") { rhs = String(rhs.dropLast()) }

            guard lhs.hasPrefix("\""), lhs.hasSuffix("\""),
                  rhs.hasPrefix("\""), rhs.hasSuffix("\"")
            else { continue }

            let key = unescape(String(lhs.dropFirst().dropLast()))
            let value = unescape(String(rhs.dropFirst().dropLast()))
            if !key.isEmpty { table[key] = value }
        }
        return table
    }

    private static func unescape(_ token: String) -> String {
        // Drops the surrounding quotes and resolves the escapes inside.
        var body = token
        if body.hasPrefix("\""), body.hasSuffix("\"") {
            body = String(body.dropFirst().dropLast())
        }

        var out = ""
        var chars = Array(body)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "\\", index + 1 < chars.count {
                let escape = chars[index + 1]
                switch escape {
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "0": out.append("\0")
                case "U": out.append("\\U")
                case "u": out.append("\\u")
                default: out.append(escape)
                }
                index += 2
            } else {
                out.append(character)
                index += 1
            }
        }
        return out
    }
}
