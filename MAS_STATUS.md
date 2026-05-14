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

## What needs Xcode UI work (next session)

Things that can't be done from CLI without project-file surgery:

1. **Add the App Store target.**
   - Duplicate the existing `Docky` target → "Docky (App Store)".
   - In Project navigator → Project → Info → Configurations, add
     "Debug (App Store)" and "Release (App Store)" using
     `Docky/Docky.AppStore.xcconfig` as the base.
   - Verify `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for the new
     configurations includes `APP_STORE_SANDBOX`.
   - Add a matching scheme.

2. **Add the Docky Helper target.**
   - File → New → Target → macOS → App, name "Docky Helper",
     bundle id `gt.quintero.Docky.Helper`, no Storyboard.
   - Add `DockyHelper/Sources/` to that target.
   - Set signing to Developer ID Application (NOT App Store).
   - Add `LSUIElement = true` to its Info.plist (faceless agent).
   - Set `EnableAppSandbox = NO` (helper is the un-sandboxed bit).
   - Set `EnableHardenedRuntime = YES` (notarization requirement).
   - Add LaunchAgent plist as a bundled resource at
     `Contents/Library/LaunchAgents/gt.quintero.Docky.Helper.plist`
     declaring `MachServices = { "gt.quintero.Docky.Helper" = true }`.
   - Add `com.apple.security.application-groups` entitlement matching
     the MAS app's group (`$(TeamIdentifierPrefix)gt.quintero.Docky.shared`).

3. **App Store Connect setup.**
   - Register App ID `gt.quintero.Docky.appstore`.
   - Register App Group `gt.quintero.Docky.shared`.
   - Bind both to the Docky team.

4. **Replace `<TEAM_ID_PLACEHOLDER>` in
   `DockyHelper/Sources/HelperListener.swift:75`** with the actual
   Team ID.

5. **First MAS validation build.** Run the App Store scheme through
   Archive → Validate to confirm:
   - No private framework references in the binary.
   - Entitlements parse cleanly.
   - Bundle contains no `.pl` / no `MediaRemoteAdapter.framework`.

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
