# Docky Helper

Side-loaded Developer ID companion for the App Store / sandboxed
build of Docky. The MAS app is fully functional standalone; this
helper unlocks the features that need private macOS APIs (SkyLight
blur, MediaRemote, system Dock control, etc).

## Architecture

```
┌──────────────────────────┐        XPC over Mach service        ┌─────────────────────────┐
│ Docky.app                │  ──────────────────────────────▶    │ DockyHelper.app         │
│  (Mac App Store, sandbox)│      gt.quintero.Docky.Helper      │  (Developer ID, side)   │
│                          │  ◀──────────────────────────────    │                         │
│  HelperBridge.shared     │   DockyHelperProtocol replies      │  HelperListener         │
└──────────────────────────┘                                     └─────────────────────────┘
```

Both bundles are signed under the same Team ID. The helper's
`NSXPCListenerDelegate` verifies the peer's `audit_token` via
`SecCodeCheckValidity` against an `SecRequirement` pinning that
Team ID, so the connection refuses any caller that isn't Docky.

## Xcode setup (one-time)

1. In the existing `Docky.xcodeproj`, add a new target:
   - Template: macOS → App
   - Product Name: `Docky Helper`
   - Bundle Identifier: `gt.quintero.Docky.Helper`
   - Language: Swift, no Storyboard, no tests, no Core Data
2. Add this directory's `Sources/` to that target.
3. Set the helper's signing to Developer ID Application (not App
   Store).
4. Add `com.apple.security.application-groups` →
   `$(TeamIdentifierPrefix)gt.quintero.Docky.shared` to the helper's
   entitlements so it can share data with the MAS app.
5. Bundle a `Contents/Library/LaunchAgents/gt.quintero.Docky.Helper.plist`
   that declares `MachServices = { "gt.quintero.Docky.Helper" = true }`
   and `RunAtLoad = true`.
6. Ship the helper via Sparkle from `getdocky.com`. Not on the App
   Store (App Review rejects "helpers for sandbox workarounds").

## Why XPC over TCP localhost

| | TCP localhost | XPC Mach service |
|---|---|---|
| Auth | Hand-rolled HMAC | Free: `audit_token` + `SecCodeCheckValidity` |
| Discovery | Port number, can collide | Globally unique service name |
| Lifecycle | Helper must be running | launchd starts on demand |
| Type safety | JSON over a stream | `NSXPCInterface` |
| Visibility | Any process can `lsof -i :PORT` | Not enumerable |
| Review optics | "Hand-rolled workaround" | Standard helper-app pattern |

## What the helper vends today

Stub. `ping(reply:)` returning `"pong:v1"` is the only method. Real
methods (focusWindow, applyBlur, mediaSnapshot, hideSystemDock,
captureWindow, etc) are added as the bridge wraps each
private-API call site on the MAS side.
