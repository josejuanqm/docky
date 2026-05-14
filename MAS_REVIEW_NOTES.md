# App Review Notes — Docky (Mac App Store build)

These notes paste into the "Notes for Reviewer" field at App Store
Connect submission time. They explain every entitlement that isn't
strictly default-sandbox-only.

---

## What Docky is

A themeable dock replacement for macOS. Pinned apps, widgets
(Calendar, Reminders, Weather, Batteries, System Status), and a
search affordance. The app coexists with the system Dock; it does
not replace or hide it in this App Store build.

## Why we need each non-default entitlement

### `com.apple.security.network.client`
- Sparkle update checks against `getdocky.com`
- Sentry crash reporting
- Gumroad license verification (`api.gumroad.com`)
- Trial-extension webhook (`getdocky.com/api/trial`)
- Weather widget (Apple-hosted WeatherKit)

### `com.apple.security.files.user-selected.read-write`
- The "Pin Application" flow uses `NSOpenPanel` to let the user
  pick a `.app` bundle; we persist a security-scoped bookmark.
- Folder tiles: user picks a folder via `NSOpenPanel`; bookmarked
  and enumerated for the folder popover.
- Feedback flow: user attaches a screenshot / video to the
  diagnostic bundle.

### `com.apple.security.files.bookmarks.app-scope`
- Required to resolve the bookmarks above on subsequent launches.

### `com.apple.security.files.downloads.read-only`
### `com.apple.security.assets.pictures.read-only`
### `com.apple.security.assets.movies.read-only`
- `NSOpenPanel` for the feedback attachment surfaces files from
  these locations; without the entitlements, those locations show
  empty.

### `com.apple.security.personal-information.calendars`
- Calendar widget reads the user's events via EventKit. Standard
  EKEventStore consent prompt is shown on first use.

### `com.apple.security.personal-information.reminders`
- Reminders widget reads via EventKit. Same consent flow.

### `com.apple.security.personal-information.location`
- Weather widget asks CoreLocation for the current location. Used
  only to fetch local conditions via WeatherKit; never logged,
  persisted, or transmitted off-device beyond the WeatherKit
  request.

### `com.apple.security.temporary-exception.apple-events` → `["com.apple.Music", "com.spotify.client"]`
- The Now Playing widget's metadata fallback path uses AppleScript
  ("tell application "Music" to get name of current track"). This
  is the legacy code path that ran before the side-loaded helper
  arrived; it remains for the small set of users who don't install
  the helper but do listen via the Music or Spotify apps.
- No control commands are sent; only read-only metadata queries.

### `com.apple.security.temporary-exception.mach-lookup.global-name` → `["gt.quintero.Docky.Helper"]`
- Docky has an optional companion app, "Docky Helper", distributed
  separately as a Developer ID-signed download from getdocky.com.
- The helper is NOT bundled with this App Store version, is NOT
  required for the app to function, and is NOT advertised via any
  in-app "download our helper" CTA that would qualify as
  cross-promotion.
- When the user has independently installed the helper, Docky
  opens an XPC connection to it for advanced features (window
  control via Accessibility, system Dock interaction). The
  connection is verified via `audit_token` + `SecCodeCheckValidity`
  pinning to our Team ID, so the helper cannot be reached by any
  other process on the system.
- App Store Docky is fully usable without the helper. Hidden
  features remain hidden when the helper isn't reachable.

### `com.apple.security.application-groups` → `$(TeamIdentifierPrefix)gt.quintero.Docky.shared`
- Shared container with the helper for license-state mirroring
  and protocol-version handshake.

## What Docky deliberately does NOT do in the App Store build

- Does not call any private framework or private CoreGraphics
  Services (SkyLight) API. The Developer ID source tree contains
  such code, but it's gated out via `#if !APP_STORE_SANDBOX` and
  not present in this binary.
- Does not invoke `/usr/bin/*` subprocesses.
- Does not write to `com.apple.dock` preferences or terminate
  the system Dock.
- Does not bundle the `mediaremote-adapter.pl` or
  `MediaRemoteAdapter.framework` resources (excluded at build
  via `EXCLUDED_SOURCE_FILE_NAMES`).
- Does not download, install, or update any executable content at
  runtime. The optional helper is an entirely separate user-driven
  install from our website.

## Build-clean verification

Before each submission we run `scripts/check-mas-clean.sh`, which
greps the Swift sources for known private-API patterns and fails
if any are found outside an `APP_STORE_SANDBOX` gate. The latest
run shows zero leaks.

## Demo account

n/a — Docky is a single-user app with no remote account.

## Contact

Jose Quintero <jose.juan.qm@gmail.com>
