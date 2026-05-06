//
//  WindowManagementSettingsView.swift
//  Docky
//

import SwiftUI

struct WindowManagementSettingsView: View {
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
    @ObservedObject private var permissions = PermissionsService.shared
    @State private var isRecordingShortcut = false

    private var resolvedLayout: WindowSwitcherLayout {
        preferences.windowSwitcherLayout
            .resolved(canCaptureThumbnails: permissions.screenCapture == .granted)
    }

    private var previewControlsApply: Bool {
        // Preview modes (in-place / instant-focus) only do anything in the
        // thumbnail layout. In list mode the list is the preview substitute.
        resolvedLayout == .thumbnails
    }

    private var shortcutHelpText: String {
        if product.isUnlocked(.windowSwitcher),
           preferences.showsWindowSwitcherFocusPreview,
           preferences.windowSwitcherPreviewMode == .instantFocus,
           previewControlsApply {
            return "While the switcher is open, keep the shortcut modifiers held and tap the shortcut again to cycle. In Instant Focus mode, each step immediately focuses the next window and releasing the modifiers ends cycling."
        }

        return "While the switcher is open, keep the shortcut modifiers held and tap the shortcut again to cycle. Release the modifiers to focus the selected window."
    }

    var body: some View {
        Form {
            Section("Window Switcher") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Window Switcher", isOn: $preferences.enablesWindowSwitcher)
                        .font(.headline)

                    Text("Turn Docky's Cmd-Tab-style switcher on or off without clearing its shortcut or preview preference.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shortcut")
                                .font(.headline)

                            Text("Choose the global shortcut that opens Docky's Cmd-Tab-style window switcher.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        ShortcutRecorderControl(
                            shortcut: preferences.windowSwitcherShortcut,
                            isRecording: $isRecordingShortcut,
                            resetShortcut: KeyboardShortcut(keyCode: 48, modifierFlags: [.option])
                        ) { shortcut in
                            preferences.windowSwitcherShortcut = shortcut
                        }
                        .disabled(!preferences.enablesWindowSwitcher)
                    }

                    Text(shortcutHelpText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                if !product.isUnlocked(.windowSwitcher) {
                    Text("Docky Pro unlocks switcher preview modes and window context menus inside the switcher.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Layout")
                        .font(.headline)

                    Picker("Layout", selection: $preferences.windowSwitcherLayout) {
                        ForEach(WindowSwitcherLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(!preferences.enablesWindowSwitcher)

                    Text(preferences.windowSwitcherLayout.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if preferences.windowSwitcherLayout == .auto, permissions.screenCapture != .granted {
                        Text("Auto is using the list right now because Screen Recording permission isn't granted.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Switcher Preview", isOn: $preferences.showsWindowSwitcherFocusPreview)
                        .font(.headline)
                        .disabled(!product.isUnlocked(.windowSwitcher) || !preferences.enablesWindowSwitcher || !previewControlsApply)

                    Text(previewControlsApply
                         ? "Choose whether the switcher should stay purely overlaid, preview the selected window behind it, or focus each step immediately while cycling."
                         : "Preview modes only apply to the Thumbnails layout. The List layout uses the row list itself as the preview.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview Mode")
                        .font(.headline)

                    Picker("Preview Mode", selection: $preferences.windowSwitcherPreviewMode) {
                        ForEach(WindowSwitcherPreviewMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(!product.isUnlocked(.windowSwitcher) || !preferences.enablesWindowSwitcher || !preferences.showsWindowSwitcherFocusPreview || !previewControlsApply)

                    Text(preferences.windowSwitcherPreviewMode.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Window Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hover Delay")
                            .font(.headline)

                        Spacer()

                        HStack {
                            Slider(value: $preferences.windowPreviewHoverDelay, in: 0...2, step: 0.05) {
                                Text("Hover Delay")
                            }
                            .labelsHidden()

                            Text(String(format: "%.2fs", preferences.windowPreviewHoverDelay))
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }

                    Text("How long to wait before the per-tile window preview appears when hovering an app or app folder.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Layout")
                        .font(.headline)

                    Picker("Layout", selection: $preferences.windowPreviewLayout) {
                        ForEach(WindowSwitcherLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(preferences.windowPreviewLayout.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if preferences.windowPreviewLayout == .auto, permissions.screenCapture != .granted {
                        Text("Auto is using the list right now because Screen Recording permission isn't granted.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}
