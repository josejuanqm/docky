//
//  WindowManagementSettingsView.swift
//  Docky
//

import SwiftUI

struct WindowManagementSettingsView: View {
    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
    @ObservedObject private var permissions = PermissionsService.shared
    @State private var isRecordingShortcut = false
    @State private var isRecordingMinimizeKey = false
    @State private var isRecordingCloseKey = false
    @State private var isRecordingZoomKey = false

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
                if !product.isUnlocked(.windowSwitcher) {
                    ProFeatureNotice(feature: .windowSwitcher)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Window Switcher", isOn: $preferences.enablesWindowSwitcher)
                        .font(.headline)
                        .disabled(!product.isUnlocked(.windowSwitcher))

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
                        .disabled(!product.isUnlocked(.windowSwitcher) || !preferences.enablesWindowSwitcher)
                    }

                    Text(shortcutHelpText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

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
                    .disabled(!product.isUnlocked(.windowSwitcher) || !preferences.enablesWindowSwitcher)

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

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Action Keys")
                            .font(.headline)
                        Text("Single-key shortcuts that fire while the switcher is open and you're still holding its modifier. Re-bind to any key; navigation keys (Tab, arrows, Escape, Return) always win over a conflicting binding.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    actionKeyRow(
                        title: "Minimize",
                        keyCode: preferences.switcherMinimizeKeyCode,
                        isRecording: $isRecordingMinimizeKey,
                        defaultKeyCode: 46
                    ) { preferences.switcherMinimizeKeyCode = $0 }

                    actionKeyRow(
                        title: "Close Window",
                        keyCode: preferences.switcherCloseKeyCode,
                        isRecording: $isRecordingCloseKey,
                        defaultKeyCode: 13
                    ) { preferences.switcherCloseKeyCode = $0 }

                    actionKeyRow(
                        title: "Zoom",
                        keyCode: preferences.switcherZoomKeyCode,
                        isRecording: $isRecordingZoomKey,
                        defaultKeyCode: 6
                    ) { preferences.switcherZoomKeyCode = $0 }
                }
                .padding(.vertical, 4)
                .disabled(!product.isUnlocked(.windowSwitcher) || !preferences.enablesWindowSwitcher)
            }

            Section("Window Preview") {
                if !product.isUnlocked(.windowSwitcher) {
                    ProFeatureNotice(feature: .windowSwitcher)
                }

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
                    .disabled(!product.isUnlocked(.windowSwitcher))

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
                    .disabled(!product.isUnlocked(.windowSwitcher))

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

    private func actionKeyRow(
        title: String,
        keyCode: UInt16,
        isRecording: Binding<Bool>,
        defaultKeyCode: UInt16,
        onChange: @escaping (UInt16) -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            SingleKeyRecorderControl(
                keyCode: keyCode,
                isRecording: isRecording,
                defaultKeyCode: defaultKeyCode,
                onChange: onChange
            )
        }
    }
}

private struct SingleKeyRecorderControl: View {
    let keyCode: UInt16
    @Binding var isRecording: Bool
    let defaultKeyCode: UInt16
    let onChange: (UInt16) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(isRecording ? "Press Key" : KeyboardShortcut.keyDisplayString(for: keyCode)) {
                isRecording = true
            }
            .buttonStyle(.borderedProminent)

            Button("Reset") {
                onChange(defaultKeyCode)
                isRecording = false
            }
            .buttonStyle(.bordered)
            .disabled(keyCode == defaultKeyCode)
        }
        .background {
            SingleKeyRecorderMonitor(
                isRecording: isRecording,
                onKey: { event in
                    onChange(event.keyCode)
                    isRecording = false
                },
                onCancel: { isRecording = false }
            )
        }
    }
}

private struct SingleKeyRecorderMonitor: NSViewRepresentable {
    let isRecording: Bool
    let onKey: (NSEvent) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKey: onKey, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(isRecording: isRecording)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKey = onKey
        context.coordinator.onCancel = onCancel
        context.coordinator.update(isRecording: isRecording)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onKey: (NSEvent) -> Void
        var onCancel: () -> Void
        private var localKeyMonitor: Any?

        init(onKey: @escaping (NSEvent) -> Void, onCancel: @escaping () -> Void) {
            self.onKey = onKey
            self.onCancel = onCancel
        }

        func update(isRecording: Bool) {
            isRecording ? start() : stop()
        }

        func start() {
            guard localKeyMonitor == nil else { return }
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }

                if event.keyCode == 53 {
                    self.onCancel()
                    return nil
                }

                self.onKey(event)
                return nil
            }
        }

        func stop() {
            guard let localKeyMonitor else { return }
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}
