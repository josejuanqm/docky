# Internationalization

Docky ships English as its source language and uses Apple's standard string
catalog (`Docky/Localizable.xcstrings`) for everything the SwiftUI layer renders.
This document explains how to add a language, and which call sites need manual
attention because their APIs do not accept a `LocalizedStringKey`.

### Shipped languages

| Region | Files | Selected by |
|---|---|---|
| `en` (source) | `Localizable.xcstrings` | — |
| `es` | `Localizable.xcstrings`, `es.lproj` | macOS |
| `fr` | `Localizable.xcstrings`, `fr.lproj` | In-app picker |
| `zh-Hans` | `Localizable.xcstrings`, `zh-Hans.lproj` | In-app picker |
| `zh-Hant` (Taiwan) | `Localizable.xcstrings`, `zh-Hant.lproj` | In-app picker |
| `zh-HK` (Hong Kong) | `Localizable.xcstrings`, `zh-HK.lproj` | In-app picker |

Except for English, all of them are chosen inside **Settings → Application →
Language** rather than in *System Settings → Language & Region*. See
[In-app language](#in-app-language).

## How localization works here

| Surface | Mechanism | Needs manual work? |
|---|---|---|
| `Text`, `Button`, `Label`, `Toggle`, `Picker`, `Section`, `TextField`, `Menu`, `Link` | SwiftUI resolves the literal as a `LocalizedStringKey` against the catalog | No |
| `NSAlert` (`messageText`, `informativeText`, `addButton(withTitle:)`) | `String`-based API | Yes — wrap in `L10n.text(_:)` |
| `NSMenuItem(title:)`, `NSMenu(title:)` | `String`-based API | Yes |
| `View.help(_:)`, `View.navigationTitle(_:)` | Takes `StringProtocol`; the literal is **not** localized | Yes |
| `View.accessibilityLabel(_:)` | `String`-based API | Yes |
| Action / package titles from `MenuCatalog/*.json` | Runtime data, not part of the catalog | Yes — handled in `MenuCatalogService.resolvedTitle(for:context:)` |
| `MainMenu.xib` | Base Internationalization | Yes — add `<lang>.lproj/MainMenu.strings` |

`L10n` (`Docky/Services/L10n.swift`) is the thin helper for the `String` cases.
It falls back to the key itself when a translation is missing, so a partial
translation degrades to readable English rather than a blank label.

## In-app language

`LanguageManager` (`Docky/Services/LanguageManager.swift`) lets the user override
the macOS language for Docky alone, from **Settings → Application → Language**.
Getting that right takes three pieces, because the main menu is loaded before
any Swift in the app runs.

**1. A `Bundle.main` override — everything Swift resolves.**
`installOverride()` replaces `Bundle.main.localizedString(forKey:value:table:)`.
That one method backs both SwiftUI's automatic `LocalizedStringKey` resolution
*and* every `String`-based call site, so the override covers all of them at
once. It reads the `.strings` files Xcode already compiled into
`Contents/Resources/<region>.lproj/` — a property list for `Localizable`, plain
text for `MainMenu` — and falls through to Foundation's original
implementation whenever the language is "Follow System" or a key has no
translation, which keeps behaviour identical to a stock build.

**2. A menu re-title pass — the main menu.**
`NSApplicationMain` loads `MainMenu.xib` before the app delegate runs, so its
titles are already fixed by the time (1) is installed. `localizeMainMenu()`
walks the live menu and swaps each title into the target region's. The
ObjectIDs line every `MainMenu.strings` table up, so a title-to-title map is
enough — no nib surgery, no private API. It runs just before
`configureMainMenu()`, which looks items up by title.

Which language the nib settled on cannot be queried, and guessing from
`preferredLocalizations` does not work: writing `AppleLanguages` updates that
list inside the running process, so it already reports the *target* by the time
this runs. Every shipped language is therefore treated as a possible source.
That is why `en.lproj/MainMenu.strings` exists — not as a localization, but as
the record of the nib's own titles, which `Base.lproj/MainMenu.nib` cannot
expose at runtime. An English-language Mac is a supported case, not a nicety.

**3. The per-app `AppleLanguages` list — best effort for the next launch.**
`applyToPerAppLanguageList()` mirrors the choice into the app's own
`AppleLanguages` preference, which is what macOS consults *when the nib loads*.
Useful when something outside the app writes that key, and it costs nothing.
Two caveats learned the hard way:

- macOS **ignores an app writing that key at runtime**, so (2) is what makes a
  switch take effect. This entry is a convenience, not the mechanism.
- Write **only** the selected region. macOS seeds the key with the system
  language while the app runs, and those region codes carry a script suffix
  (`zh-Hans-CN`) matching no `.lproj` on disk; appending them makes the whole
  list fail to resolve and Docky silently falls back to the system language.
- Do **not** add `CFBundleLocalizations` to `Config/Info.plist` to help with
  this. Doing so makes macOS validate the list against it and reject the whole
  array, which breaks even languages that otherwise work.

A language change restarts Docky. Not for the menu — (2) handles that live — but
because the rest of the interface is composed once per process and rebuilding
it in place is not worth the churn.

### Adding a language to the picker

Ship the `.lproj` and the catalog column (the four steps below), then add a
case to `AppLanguage` — one `region`, one `endonym`. `AllCases` drives the
picker; nothing else references the list.

## Adding a language

1. **Open the catalog.** In Xcode, select `Localizable.xcstrings` → the
   `+` in the inspector → *Add Language*. Xcode registers the region in
   `knownRegions` for you.
2. **Translate the app strings.** Fill in the new language column. Keys are
   plain English sentences, and the `comment` on each key explains the context
   (what the arguments mean, where the string appears).
3. **Translate the main menu.** Duplicate an existing localization as a
   starting point — `es.lproj/MainMenu.strings` is the reference:

   ```
   cp Docky/es.lproj/MainMenu.strings Docky/<lang>.lproj/MainMenu.strings
   ```

   Each entry is keyed by the XIB ObjectID (for example
   `"5kV-Vb-QxS.title" = "About Docky";`). The ObjectIDs must not change; only
   the values do. The app-menu title (`1Xt-HY-uBw`) and any product name should
   stay untranslated.
4. **Add the region** if Xcode did not already: add the language code to
   `knownRegions` in `Docky.xcodeproj/project.pbxproj`.

No code changes are needed — the target uses
`PBXFileSystemSynchronizedRootGroup`, so new `.lproj` folders are picked up
automatically.

## Placeholders

Format specifiers must survive translation untouched, in the same **type**:

- `%@` — `String` (or any object)
- `%lld` — `Int` / `Int64`

Two rules matter:

1. **Never renumber blindly.** If the translated word order differs from the
   English, use explicit positional specifiers (`%1$@`, `%2$lld`) so each
   argument lands in the right place. Keep the specifier *type* attached to the
   same argument as the original — swapping `%1$@` and `%2$lld` produces
   garbage.
2. **Chinese reordering example.** `"Step %lld of %lld"` takes the current step
   first and the total second. The correct Chinese translation is
   `"第 %1$lld 步，共 %2$lld 步"` — same order as the source, explicitly
   numbered to make the binding unambiguous.

## Adding new user-facing strings

- **In a SwiftUI view**, just write the literal: `Text("Add Widget")`. Xcode
  extracts it into the catalog on build. Then add the new language's
  translation.
- **Anywhere that takes a `String`**, use `L10n.text(_:)`:

  ```swift
  alert.messageText = L10n.text("Could not import theme")
  alert.addButton(withTitle: L10n.text("OK"))
  .help(L10n.text("Reveal in Finder"))
  ```

  With arguments, pass them through:

  ```swift
  alert.informativeText = L10n.text("Show More (%lld)", overflowCount)
  ```

- **For a new catalog action**, add an `action.<id>` key so the title can be
  translated without touching `actions.json`, and route it through
  `L10n.catalogText(id:fallback:)`. If the action has an `alternateTitle`, use
  `action.<id>.option` for it.
