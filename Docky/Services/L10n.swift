import Foundation

/// Localization helpers for call sites whose APIs take a `String` rather than a
/// `LocalizedStringKey`.
///
/// SwiftUI's `Text`, `Button`, `Label`, `Toggle`, `Picker`, `Section`,
/// `TextField` and friends already resolve string literals against
/// `Localizable.xcstrings` automatically. Everything else — `NSAlert`,
/// `NSMenuItem`, `View.help(_:)`, `View.navigationTitle(_:)`, accessibility
/// labels, and the titles loaded from `MenuCatalog/*.json` — takes a
/// `StringProtocol` and therefore never gets translated.
///
/// Use `L10n.text(_:)` for a bare key, and the `format` overloads when the key
/// carries positional arguments. Keys are plain English sentences so the
/// catalog stays readable and translators get the context they need.
enum L10n {
    /// Looks up `key` in the string catalog, falling back to the key itself so a
    /// missing translation degrades to readable English instead of an empty
    /// label.
    static func text(_ key: String) -> String {
        let value = NSLocalizedString(key, comment: "")
        return value.isEmpty ? key : value
    }

    /// Looks up a catalog entry built from `key` plus its arguments, matching how
    /// SwiftUI formats interpolated literals (for example
    /// `"Show More (\(count))"` is stored as `"Show More (%lld)"`).
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    /// Translates an action or menu title loaded from a `MenuCatalog` JSON file.
    ///
    /// Catalog data ships in English and is not part of the string catalog, so
    /// the lookup falls back through two levels: a `<packageID>.<actionID>`
    /// key first (allowing per-action wording that differs from the generic
    /// title), then the title itself. Both live in `Localizable.xcstrings`.
    static func catalogText(id: String, fallback: String) -> String {
        let scoped = "action.\(id)"
        let scopedValue = NSLocalizedString(scoped, comment: "")
        if !scopedValue.isEmpty, scopedValue != scoped { return scopedValue }

        let value = NSLocalizedString(fallback, comment: "")
        return value.isEmpty ? fallback : value
    }
}
