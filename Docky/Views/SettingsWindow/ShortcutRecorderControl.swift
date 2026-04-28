//
//  ShortcutRecorderControl.swift
//  Docky
//

import SwiftUI

struct ShortcutRecorderControl: View {
    let shortcut: KeyboardShortcut
    @Binding var isRecording: Bool
    let resetShortcut: KeyboardShortcut?
    let onChange: (KeyboardShortcut) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(isRecording ? "Type Shortcut" : shortcut.displayString) {
                isRecording = true
            }
            .buttonStyle(.borderedProminent)

            Button(resetShortcut == nil ? "Clear" : "Reset") {
                onChange(resetShortcut ?? .empty)
                isRecording = false
            }
            .buttonStyle(.bordered)
            .disabled(isRecording && shortcut == (resetShortcut ?? .empty))
        }
        .background {
            ShortcutRecorderMonitor(
                isRecording: isRecording,
                onShortcut: { event in
                    guard let shortcut = KeyboardShortcut.from(event: event) else {
                        return false
                    }

                    onChange(shortcut)
                    isRecording = false
                    return true
                },
                onCancel: {
                    isRecording = false
                }
            )
        }
    }
}

private struct ShortcutRecorderMonitor: NSViewRepresentable {
    let isRecording: Bool
    let onShortcut: (NSEvent) -> Bool
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onShortcut: onShortcut, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(isRecording: isRecording)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onShortcut = onShortcut
        context.coordinator.onCancel = onCancel
        context.coordinator.update(isRecording: isRecording)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onShortcut: (NSEvent) -> Bool
        var onCancel: () -> Void
        private var localKeyMonitor: Any?

        init(onShortcut: @escaping (NSEvent) -> Bool, onCancel: @escaping () -> Void) {
            self.onShortcut = onShortcut
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

                return self.onShortcut(event) ? nil : event
            }
        }

        func stop() {
            guard let localKeyMonitor else { return }
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}
