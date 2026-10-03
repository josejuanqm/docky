//
//  LaunchpadSettingsView.swift
//  Docky
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LaunchpadSettingsView: View {
    /// Hides the "Availability" section (Pro upsell + global enable
    /// toggle). The detached inspector that floats over the launchpad
    /// sets this so users live-tuning the grid don't see a switch that
    /// would hide the very surface they're standing on.
    var hidesAvailabilitySection: Bool = false

    @Bindable private var preferences = DockyPreferences.shared
    @State private var isRecordingShortcut = false

    var body: some View {
        Form {
            if !hidesAvailabilitySection {
                Section("Availability") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable Launchpad", isOn: $preferences.enablesLaunchpadOverlay)
                            .font(.headline)

                        Text("Turn Docky's Launchpad overlay on or off without removing its shortcut or layout preferences.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Shortcut") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Global Shortcut")
                                .font(.headline)

                            Text("Optionally assign a global shortcut that toggles Docky's Launchpad overlay from anywhere.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        ShortcutRecorderControl(
                            shortcut: preferences.launchpadShortcut,
                            isRecording: $isRecordingShortcut,
                            resetShortcut: nil
                        ) { shortcut in
                            preferences.launchpadShortcut = shortcut
                        }
                        .disabled(!preferences.enablesLaunchpadOverlay)
                    }

                    Text("Leave this unset if you only want to open Launchpad from the Docky tile or context menu.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Layout") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Scroll Direction")
                            .font(.headline)

                        Spacer()

                        Picker("Scroll Direction", selection: $preferences.launchpadLayoutAxis) {
                            ForEach(LaunchpadLayoutAxis.allCases) { axis in
                                Text(L10n.text(axis.title)).tag(axis)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .disabled(!preferences.enablesLaunchpadOverlay)
                    }

                    Text(preferences.launchpadLayoutAxis.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack {
                        Text("Grid Columns")
                            .font(.headline)

                        Spacer()

                        Stepper("\(preferences.launchpadGridColumnCount)", value: $preferences.launchpadGridColumnCount, in: 1...12)
                            .foregroundStyle(.secondary)
                            .disabled(!preferences.enablesLaunchpadOverlay)
                    }

                    HStack {
                        Text("Grid Rows")
                            .font(.headline)

                        Spacer()

                        Stepper("\(preferences.launchpadGridRowCount)", value: $preferences.launchpadGridRowCount, in: 1...10)
                            .foregroundStyle(.secondary)
                            // Rows are only consulted in paged mode;
                            // vertical mode grows as long as needed.
                            .disabled(!preferences.enablesLaunchpadOverlay
                                      || preferences.launchpadLayoutAxis == .vertical)
                    }

                    Text("Sets the Launchpad grid dimensions. Docky uses these counts when the icons fit on screen, defaulting to 7 columns × 5 rows. Row count is ignored when scroll direction is continuous.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack {
                        Text("Icon Size")
                            .font(.headline)

                        Spacer()

                        Text("\(Int(preferences.launchpadBaseIconSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $preferences.launchpadBaseIconSize,
                        in: 48...192,
                        step: 1
                    )
                    .disabled(!preferences.enablesLaunchpadOverlay)

                    Text("Maximum icon edge on a 1440p screen. Smaller displays scale down from this value; larger ones are clamped to it. Default is 128 pt.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack {
                        Text("Column Spacing")
                            .font(.headline)

                        Spacer()

                        Text("\(Int(preferences.launchpadColumnSpacing)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $preferences.launchpadColumnSpacing,
                        in: 0...96,
                        step: 1
                    )
                    .disabled(!preferences.enablesLaunchpadOverlay)

                    Text("Horizontal gap between icons at the reference height. Lower values pack icons tighter, higher values spread them out.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transparency")
                            .font(.headline)

                        Spacer()

                        Text("\(Int(preferences.launchpadOverlayTransparency * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: launchpadTransparencyBinding, in: 0...1, step: 0.01)
                        .disabled(!preferences.enablesLaunchpadOverlay)

                    Text("Adjusts how transparent the Launchpad backdrop is. Lower values darken the screen behind the grid; higher values let more of your desktop show through.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Background Image")
                        .font(.headline)

                    HStack {
                        Button("Choose Image…") {
                            chooseBackgroundImage()
                        }
                        .disabled(!preferences.enablesLaunchpadOverlay)

                        if preferences.launchpadBackgroundImagePath != nil {
                            Button("Use Desktop Wallpaper") {
                                preferences.launchpadBackgroundImagePath = nil
                            }
                        }
                    }

                    if let name = selectedBackgroundImageName {
                        Text(name)
                            .foregroundStyle(.secondary)
                    }

                    Text("Pick an image to render behind the Launchpad grid. When unset, Docky uses the current desktop wallpaper. Combined with the transparency slider for the dim overlay above it.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Blur Background Image", isOn: $preferences.launchpadBackgroundBlursImage)
                        .disabled(!preferences.enablesLaunchpadOverlay)

                    Text("Turn off to render the chosen image crisp. Default is on to soften the desktop wallpaper into a neutral backdrop.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private var launchpadTransparencyBinding: Binding<CGFloat> {
        Binding(
            get: { preferences.launchpadOverlayTransparency },
            set: { preferences.launchpadOverlayTransparency = min(max($0, 0), 1) }
        )
    }

    private var selectedBackgroundImageName: String? {
        guard let path = preferences.launchpadBackgroundImagePath, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// Where the file picker should land on open. Re-uses the parent
    /// folder of whatever the user picked last (lets them iterate
    /// inside a curated wallpapers directory); otherwise jumps to the
    /// system desktop pictures folder so the OS-provided images are one
    /// click away.
    private func startingDirectoryForBackgroundImagePicker() -> URL? {
        if let path = preferences.launchpadBackgroundImagePath, !path.isEmpty {
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        return defaultDesktopPicturesDirectory()
    }

    /// First on-disk location that holds Apple's bundled desktop
    /// pictures. The classic flat folder still exists on every shipping
    /// macOS, so it stays at the top of the list; the modern
    /// `Wallpapers` folder is intentionally not tried because it
    /// contains `.wallpaper` packages, not pickable image files.
    /// Falls back to the user's Pictures folder when neither system
    /// path exists (defensive against future macOS versions).
    private func defaultDesktopPicturesDirectory() -> URL? {
        let candidates = [
            "/System/Library/Desktop Pictures",
            "/Library/Desktop Pictures",
        ]
        for path in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"
        panel.directoryURL = startingDirectoryForBackgroundImagePicker()

        // The launchpad overlay (`.mainMenu + 1`) and the launchpad
        // inspector panel (`.mainMenu + 2`) both float above any
        // standard-level window, so a vanilla `runModal()` opens the
        // file picker behind them and the user never sees it. Attaching
        // as a sheet inherits the parent's level — works whether the
        // host is the inspector panel, the main settings window, or
        // anything else holding key focus. Fall back to a manually
        // elevated `runModal()` only when there's no key window.
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            preferences.launchpadBackgroundImagePath = url.path
        }

        if let parent = NSApp.keyWindow {
            panel.beginSheetModal(for: parent, completionHandler: completion)
        } else {
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            completion(panel.runModal())
        }
    }
}
