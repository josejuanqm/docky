<div align="center">

<img src="docs/images/logo.png" width="128" alt="Docky logo">

# Docky

### The same old dock, on steroids. Now free and open source.

Docky is a Dock replacement for macOS that elegantly replaces the system one. It
brings the Dock back into reach: quieter, smarter, and native-feeling, with a
configurable layout, widgets, a fullscreen Launchpad, a live window switcher,
custom icons, and scripted actions.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://getdocky.com)
[![Universal](https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-Universal-orange)](https://getdocky.com)
[![Website](https://img.shields.io/badge/getdocky.com-Download-brightgreen)](https://getdocky.com)

[**Download**](https://getdocky.com) &nbsp;·&nbsp; [**Website**](https://getdocky.com) &nbsp;·&nbsp; [**Build from source**](#building-from-source)

</div>

<div align="center">
  <img src="docs/images/hero.jpg" alt="Docky on macOS" width="900">
</div>

## Why Docky

The Dock is the most-used surface on a Mac, and it has barely changed in years.
Docky rebuilds it for focus: it can run alongside, mirror, or fully replace the
system Dock, and it moves with your workflow instead of getting in the way.

- **Free and open source.** No paid tier, no upsell. Licensed under GPLv3.
- **Native-feeling.** A universal binary for Apple Silicon and Intel, notarized
  by Apple.
- **Yours to shape.** Pin what you reach for, arrange it how you think, and drop
  in widgets and actions that match how you work.

## Features

### Tiles and layout

Add and arrange anything in one strip: apps, widgets, Smart Stacks, folders,
spacers, and dividers. Pin what you reach for, drag to reorder, and let the
layout follow your workflow.

<div align="center"><img src="docs/images/feature-layout.jpg" alt="Tiles and layout" width="820"></div>

### Window switcher, live

A global, Cmd-Tab-style window switcher with live window previews, plus per-tile
hover previews so you can see a window before you raise it.

<div align="center"><img src="docs/images/feature-window-switcher.jpg" alt="Live window switcher" width="820"></div>

### Built-in Launchpad

A fullscreen, searchable app launcher with full keyboard navigation, its own
layout, and an optional global shortcut.

<div align="center"><img src="docs/images/feature-launchpad.jpg" alt="Built-in Launchpad" width="820"></div>

### Widgets in the dock

Built-in widgets (Calendar, Reminders, Batteries, System, Weather, Now Playing,
and more) live right in the dock. Stack several into a single tile with **Smart
Stacks** and cycle through them in place. Add community `.dockywidget` bundles
through the widget store.

<div align="center"><img src="docs/images/feature-widgets.jpg" alt="Widgets and Smart Stacks" width="820"></div>

### Rich app folders

Group apps into folders with nested navigation, Quick Look, and drag-and-drop.
Optionally show running apps inline so a folder doubles as a live workspace.

<div align="center"><img src="docs/images/feature-folders.jpg" alt="Rich app folders" width="820"></div>

### More

- **Custom app icons:** override the icon for any pinned, running, or
  widget-backed app.
- **Scripted actions:** catalog-backed AppleScript and menu-click automation,
  plus curated commands.
- **Themes and profiles:** themeable appearance and switchable configuration
  profiles.

## Download

Get the latest notarized build from [getdocky.com](https://getdocky.com), or grab
a release from the [Releases page](https://github.com/josejuanqm/docky/releases).

### Homebrew

```sh
brew install --cask josejuanqm/tap/docky
```

Updates are delivered in-app via Sparkle. No tap trust step is needed for a normal
install. If you run Homebrew with `HOMEBREW_REQUIRE_TAP_TRUST=1`, trust the cask
first with `brew trust --cask josejuanqm/tap/docky`.

Docky needs **Accessibility** and **Screen Recording** permissions to manage
windows and render previews. It prompts for these on first launch.

> [!NOTE]
> Docky uses private SkyLight / CoreGraphics Services and Accessibility SPI (see
> `Docky/Private/`) to position windows, capture previews, and drive the system
> Dock. Because of this, **Docky cannot be distributed on the Mac App Store**.
> It is built from source or distributed directly.

## Building from source

```sh
git clone https://github.com/josejuanqm/docky.git
cd docky
open Docky.xcodeproj
```

Build and run the `Docky` scheme. Swift Package dependencies (Sparkle) resolve
automatically on first build.

You can also build from the command line:

```sh
xcodebuild -project Docky.xcodeproj -scheme Docky \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

### Requirements

- macOS 14.0 (Sonoma) or later
- The full **Xcode 16 or later** — the Command Line Tools alone are **not** enough
  (the build needs `xcodebuild` plus Xcode's bundled components)

> [!NOTE]
> **First-time Xcode setup.** On a machine where Xcode was just installed, finish
> its one-time setup before building, or the build fails on a missing toolchain:
>
> ```sh
> sudo xcodebuild -license accept
> sudo xcodebuild -runFirstLaunch
> ```
>
> Skipping these shows up as `xcode-select: error: tool 'xcodebuild' requires Xcode`,
> a "command line tools instance" warning, or `A required plugin failed to load …
> try running 'xcodebuild -runFirstLaunch'`.

## Documentation

- [External widget bundles](docs/external-widgets.md): the `.dockywidget` bundle
  contract and how to build community widgets.

## Dependencies

- [Sparkle](https://github.com/sparkle-project/Sparkle): software update
  framework (BSD 3-Clause).

## License

[GNU General Public License v3.0](LICENSE). Copyright (C) 2026 Jose Quintero.
