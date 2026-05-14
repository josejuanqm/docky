# Mac App Store Distribution — Status

The goal: ship Docky on the Mac App Store for users who only browse
there, without compromising the full Developer ID product. Sandboxed
MAS build + side-loaded Developer ID helper, communicating over XPC.
Advanced features stay hidden unless the helper is installed so the
optics are clean.

## What's done

### Code gating (done — Developer ID build is unaffected)

Every site that uses a private framework, dlopen of a private path,
private class name string, `/usr/bin/*` subprocess, or write to
`com.apple.dock` is wrapped in `#if !APP_STORE_SANDBOX`. When the
flag is undefined (today), behavior is identical to before. When
the flag is defined (the future MAS target), each site either falls
through to a public-API alternative or no-ops cleanly.

Sites gated:

| File | Symbol / surface |
|---|---|
| `Docky/Private/CGSPrivate.swift` | entire file (CGS / SkyLight bindings, dlopen, _AXUIElementGetWindow, SLPS) |
| `Docky/Private/SkyLightSpaceReservationProbe.swift` | entire file |
| `Docky/Views/Modifiers/DockyGlass.swift` | `CGSSetWindowBackgroundBlurRadius` |
| `Docky/Views/MainWindow/MainWindow.swift` | `CGSSetWindowBackgroundBlurRadius` |
| `Docky/Views/MainWindow/LaunchpadOverlayWindowController.swift` | `CGSSetWindowBackgroundBlurRadius` |
| `Docky/Views/MainWindow/MainWindowView.swift` | `NSGlassEffectView` + `set_variant:` |
| `Docky/Views/Modifiers/LiveGlassBackdrop.swift` | `CABackdropLayer`, `CAFilter` |
| `Docky/Services/WorkspaceService.swift` | `CGWindowListCreateImagePrivate` (4 sites) |
| `Docky/Services/WindowRegistry.swift` | SLPS focus, `_AXUIElementGetWindow` |
| `Docky/Services/MediaPlaybackService.swift` | MediaRemote bundle load + `/usr/bin/perl` |
| `Docky/Services/SystemDockVisibilityService.swift` | writes to `com.apple.dock`, `forceTerminate` |
| `Docky/Services/ThemeManager.swift` | `/usr/bin/ditto` (extract + create) |
| `Docky/Views/SettingsWindow/FeedbackSettingsView.swift` | `/usr/bin/ditto` |
| `Docky/AppDelegate.swift` | `/usr/bin/open` relaunch |

### UI gating (done — partial)

Surfaces that aren't operable without the helper are hidden from
the MAS build's UI entirely, rather than shown as disabled:

- **Now Playing widget**: hidden from the dock editor palette and
  smart stack via `WidgetCatalog.paletteRegistrations` / `smartStackRegistrations`
  filtering on `HelperBridge.shared.isAvailable`.
- **"Hide System Dock" toggle**: section replaced with an
  explanatory note pointing to the Developer ID version.
- **Theme import / export buttons**: hidden (themes still
  installable by dropping into `~/Library/Application Support/Docky/Themes/`).

### Foundation files (done)

- `Docky/Services/HelperBridge.swift`: `@MainActor` singleton vending
  `isAvailable: Bool`. Today always false (helper doesn't exist
  yet). The `startIfNeeded()` call wires up at app launch in
  `AppDelegate.applicationDidFinishLaunching`.
- `Docky/Docky.AppStore.entitlements`: ready-to-use entitlements
  for the MAS target (sandbox, network.client, user-selected files,
  Calendar/Reminders/Location, App Group, temp-exception for the
  helper Mach service).
- `Docky/Docky.AppStore.xcconfig`: build settings template that
  defines `APP_STORE_SANDBOX`, points to the entitlements file,
  enables sandbox + hardened runtime, and uses
  `EXCLUDED_SOURCE_FILE_NAMES` to strip the Perl helper and
  MediaRemoteAdapter framework from the MAS bundle.
- `DockyHelper/`: sibling directory with Swift sources for the
  side-loaded helper bundle (DockyHelperApp, HelperListener,
  HelperService, DockyHelperProtocol). Not yet a separate Xcode
  target; sources are ready to import.

## Targets now in the project

Both new targets created programmatically via the `xcodeproj` gem;
each builds cleanly:

```bash
$ xcodebuild -list | grep -A4 Targets:
    Targets:
        Docky                  # existing Developer ID build, unchanged
        DockyDockWatchdog
        Docky (App Store)      # sandboxed MAS build, APP_STORE_SANDBOX defined
        Docky Helper           # Developer ID helper, un-sandboxed, faceless
```

- **Docky (App Store)** built with `xcodebuild -scheme 'Docky (App Store)' build` succeeds. Bundle verified to contain no `SkyLight` / `MediaRemote.framework` string references and no embedded `mediaremote-adapter.pl` / `MediaRemoteAdapter.framework`.
- **Docky Helper** built with `xcodebuild -scheme 'Docky Helper' CODE_SIGNING_ALLOWED=NO build` succeeds locally. For distribution it needs a Developer ID Application signing identity (already configured to use Team `2KC3797KP9`).

To re-create either from scratch (if the project file is ever
corrupted), the Ruby scripts at `scripts/add-mas-target.rb` and
`scripts/add-helper-target.rb` are idempotent.

## What still requires external accounts

1. **App Store Connect setup.** Requires Apple Developer Account web access.
   - Register App ID `gt.quintero.Docky.appstore`.
   - Register App Group `gt.quintero.Docky.shared`.
   - Create App Store distribution provisioning profile.

2. **Helper code-signing identity.** Requires Developer ID Application
   certificate to be present in the Mac's Keychain. Once present, the
   helper builds and signs without further config (the Ruby script set
   `DEVELOPMENT_TEAM = 2KC3797KP9` and `CODE_SIGN_STYLE = Automatic`).

3. **App Group entitlements UI in Xcode.** Both the MAS target and the
   helper target need `com.apple.security.application-groups` ticked
   in their respective entitlement files with
   `$(TeamIdentifierPrefix)gt.quintero.Docky.shared`. The
   `Docky.AppStore.entitlements` file already declares it; the helper
   needs its own entitlements file added once the group is registered
   in App Store Connect.

4. **Archive → Validate → Distribute.** From the Xcode menu or via
   `xcodebuild archive` + `xcodebuild -exportArchive` with an App Store
   export plist that references the provisioning profile from step 1.

5. **App Store review submission.** Manual upload through App Store
   Connect or `altool` / `notarytool`.

## What's next after Xcode setup (Phase 2)

1. **Wire up `HelperBridge.startIfNeeded` for real.** Replace the
   "always false" stub with an `NSXPCConnection(machServiceName:)`
   handshake. The protocol version check (`ping → "pong:v1"`) flips
   `isAvailable`.

2. **Move private-API call sites into the helper.** For each gated
   site that has a "MAS path: no-op" today, change the gate to
   route through `HelperBridge.shared` when `isAvailable` is true.
   Start with the highest-value features:
   - `applySkyLightBlur` for the chrome (most visible).
   - `focusWindow(pid:windowID:)` for cycle-windows-on-click.
   - `currentlyPlaying` for the Now Playing widget.
   - Window thumbnails for previews.

3. **Helper distribution.** Sparkle on the helper, served from
   getdocky.com. The MAS app shows an "Install Helper" CTA in
   Settings → Themes (or a new Helper pane) when `isAvailable` is
   false.

## Kill criteria (when to stop)

From the goal definition:

- App Review rejects the Lite version twice with no clear path.
- 6 months after MAS launch, attributed MAU < 5% of total.
- Maintaining the MAS channel delays a Dev ID release.

## Verifying current state

```bash
# Dev ID build (today)
cd /Users/josequintero/source/personal/Docky
xcodebuild -scheme Docky -configuration Debug -destination 'platform=macOS' build

# Should always say BUILD SUCCEEDED. Nothing changed for Dev ID.
```

```bash
# What's left to gate (search for new private-API surface I missed)
grep -rn 'NSClassFromString("\(NS\|CA\|SL\|SK\)' Docky --include="*.swift" \
  | grep -v "#if !APP_STORE_SANDBOX"

grep -rn '/System/Library/PrivateFrameworks' Docky --include="*.swift" \
  | grep -v "#if !APP_STORE_SANDBOX" | grep -v "^Docky/Private"

grep -rn '"/usr/bin/' Docky --include="*.swift" \
  | grep -v "#if !APP_STORE_SANDBOX"
```

Both queries should return only commented-out matches today.
