//
//  WindowSwitcherService.swift
//  Docky
//

import AppKit
import Carbon
import Combine

struct FocusedWindowPreview {
    let windowIdentifier: String
    let image: NSImage
    let screenBounds: CGRect
}

final class WindowSwitcherService: ObservableObject {
    static let shared = WindowSwitcherService()

    @Published private(set) var isPresented = false
    @Published private(set) var windows: [AppWindow] = []
    @Published private(set) var selectedWindowIdentifier: String?
    @Published private(set) var isContextMenuPresented = false
    @Published private(set) var focusedPreview: FocusedWindowPreview?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var focusedPreviewTask: Task<Void, Never>?
    private let forwardHotKeyID = EventHotKeyID(signature: OSType(0x444B5957), id: 1)
    private let reverseHotKeyID = EventHotKeyID(signature: OSType(0x444B5957), id: 2)
    private var reverseHotKeyRef: EventHotKeyRef?

    private init() {
        installHotKeyHandlerIfNeeded()
        registerHotKey(shortcut: DockyPreferences.shared.windowSwitcherShortcut)
        installEventMonitors()
        subscribeToPreferences()
    }

    deinit {
        unregisterHotKey()

        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
        }
    }

    func handleHotKeyPress(direction: Int) {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "switch between windows")
            return
        }

        let latestWindows = WorkspaceService.shared.switchableWindows()
        guard !latestWindows.isEmpty else {
            dismiss()
            return
        }

        let previousSelectionIdentifier = selectedWindowIdentifier
        windows = latestWindows

        if isPresented {
            let currentIndex = previousSelectionIdentifier.flatMap { identifier in
                latestWindows.firstIndex { $0.windowIdentifier == identifier }
            } ?? 0
            selectWindow(at: currentIndex + direction)
            return
        }

        isPresented = true
        let initialIndex: Int
        if latestWindows.count <= 1 {
            initialIndex = 0
        } else if direction < 0 {
            initialIndex = latestWindows.count - 1
        } else {
            initialIndex = 1
        }
        selectWindow(at: initialIndex)
    }

    func confirmSelection() {
        guard let selectedWindow else {
            dismiss()
            return
        }

        dismiss()
        _ = WorkspaceService.shared.focus(window: selectedWindow)
    }

    func dismiss() {
        cancelFocusedPreview()
        isPresented = false
        isContextMenuPresented = false
        windows = []
        selectedWindowIdentifier = nil
    }

    func moveSelection(delta: Int) {
        guard !windows.isEmpty else { return }

        let currentIndex = selectedWindow.flatMap { window in
            windows.firstIndex { $0.windowIdentifier == window.windowIdentifier }
        } ?? 0
        selectWindow(at: currentIndex + delta)
    }

    func selectWindow(withIdentifier identifier: String) {
        guard windows.contains(where: { $0.windowIdentifier == identifier }) else {
            return
        }

        selectedWindowIdentifier = identifier

        scheduleFocusedPreview(forWindowIdentifier: identifier)
    }

    func setContextMenuPresented(_ isPresented: Bool) {
        isContextMenuPresented = isPresented

        if isPresented {
            cancelFocusedPreview()
        }

        guard !isPresented else {
            return
        }

        dismissIfShortcutReleased(flags: NSEvent.modifierFlags)
    }

    func removeWindow(withIdentifier identifier: String) {
        guard let removedIndex = windows.firstIndex(where: { $0.windowIdentifier == identifier }) else {
            return
        }

        windows.remove(at: removedIndex)

        guard !windows.isEmpty else {
            dismiss()
            return
        }

        let nextIndex = min(removedIndex, windows.count - 1)
        selectWindow(withIdentifier: windows[nextIndex].windowIdentifier)
    }

    private var selectedWindow: AppWindow? {
        guard let selectedWindowIdentifier else {
            return nil
        }

        return windows.first { $0.windowIdentifier == selectedWindowIdentifier }
    }

    private func subscribeToPreferences() {
        DockyPreferences.shared.$windowSwitcherShortcut
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shortcut in
                self?.registerHotKey(shortcut: shortcut)
            }
            .store(in: &cancellables)

        DockyPreferences.shared.$showsWindowSwitcherFocusPreview
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }

                if isEnabled, let selectedWindowIdentifier {
                    self.scheduleFocusedPreview(forWindowIdentifier: selectedWindowIdentifier)
                } else {
                    self.cancelFocusedPreview()
                }
            }
            .store(in: &cancellables)
    }

    private func installEventMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresented else {
                return event
            }

            switch event.keyCode {
            case 53:
                self.dismiss()
                return nil
            case 36, 76:
                self.confirmSelection()
                return nil
            case 123, 126:
                self.moveSelection(delta: -1)
                return nil
            case 124, 125:
                self.moveSelection(delta: 1)
                return nil
            default:
                return event
            }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierReleaseIfNeeded(flags: event.modifierFlags)
            return event
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierReleaseIfNeeded(flags: event.modifierFlags)
        }
    }

    private func handleModifierReleaseIfNeeded(flags: NSEvent.ModifierFlags) {
        guard isPresented else { return }
        guard !isContextMenuPresented else { return }

        let requiredFlags = DockyPreferences.shared.windowSwitcherShortcut.modifierFlags
        let activeFlags = flags.intersection(KeyboardShortcut.supportedModifierFlags)
        guard !requiredFlags.isEmpty, !activeFlags.isSuperset(of: requiredFlags) else {
            return
        }

        confirmSelection()
    }

    private func dismissIfShortcutReleased(flags: NSEvent.ModifierFlags) {
        guard isPresented else { return }

        let requiredFlags = DockyPreferences.shared.windowSwitcherShortcut.modifierFlags
        let activeFlags = flags.intersection(KeyboardShortcut.supportedModifierFlags)
        guard !requiredFlags.isEmpty, !activeFlags.isSuperset(of: requiredFlags) else {
            return
        }

        dismiss()
    }

    private func selectWindow(at index: Int) {
        guard !windows.isEmpty else {
            selectedWindowIdentifier = nil
            return
        }

        let wrappedIndex = ((index % windows.count) + windows.count) % windows.count
        selectWindow(withIdentifier: windows[wrappedIndex].windowIdentifier)
    }

    private func cancelFocusedPreview() {
        focusedPreviewTask?.cancel()
        focusedPreviewTask = nil
        WorkspaceService.shared.stopLiveFocusPreview()
        focusedPreview = nil
    }

    private func scheduleFocusedPreview(forWindowIdentifier identifier: String) {
        let preferences = DockyPreferences.shared

        focusedPreviewTask?.cancel()
        focusedPreviewTask = nil

        focusedPreview = nil

        guard preferences.showsWindowSwitcherFocusPreview,
              isPresented,
              !isContextMenuPresented,
              windows.contains(where: { $0.windowIdentifier == identifier }) else {
            return
        }

        focusedPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))

            await self?.runFocusedPreviewLoop(forWindowIdentifier: identifier)
        }
    }

    private func runFocusedPreviewLoop(forWindowIdentifier identifier: String) async {
        guard DockyPreferences.shared.showsWindowSwitcherFocusPreview,
              isPresented,
              !isContextMenuPresented,
              selectedWindowIdentifier == identifier,
              let window = windows.first(where: { $0.windowIdentifier == identifier }),
              let screenBounds = window.screenBounds,
              !screenBounds.isEmpty else {
            focusedPreview = nil
            return
        }

        let startedLivePreview = await WorkspaceService.shared.startLiveFocusPreview(for: window) { [weak self] image in
            guard let self,
                  self.isPresented,
                  !self.isContextMenuPresented,
                  self.selectedWindowIdentifier == identifier,
                  let image else {
                return
            }

            self.focusedPreview = FocusedWindowPreview(
                windowIdentifier: identifier,
                image: image,
                screenBounds: screenBounds
            )
        }

        guard !startedLivePreview else { return }

        while !Task.isCancelled {
            guard DockyPreferences.shared.showsWindowSwitcherFocusPreview,
                  isPresented,
                  !isContextMenuPresented,
                  selectedWindowIdentifier == identifier,
                  let currentWindow = windows.first(where: { $0.windowIdentifier == identifier }),
                  let currentScreenBounds = currentWindow.screenBounds,
                  !currentScreenBounds.isEmpty else {
                focusedPreview = nil
                return
            }

            if let image = await WorkspaceService.shared.liveFocusPreviewImage(for: currentWindow) {
                focusedPreview = FocusedWindowPreview(
                    windowIdentifier: identifier,
                    image: image,
                    screenBounds: currentScreenBounds
                )
            }

            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else {
                return OSStatus(eventNotHandledErr)
            }

            let service = Unmanaged<WindowSwitcherService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr,
                  hotKeyID.signature == service.forwardHotKeyID.signature else {
                return OSStatus(eventNotHandledErr)
            }

            let direction = hotKeyID.id == service.reverseHotKeyID.id ? -1 : 1

            Task { @MainActor in
                service.handleHotKeyPress(direction: direction)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
    }

    private func registerHotKey(shortcut: KeyboardShortcut) {
        unregisterHotKey()

        guard shortcut.isValid else {
            return
        }

        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            forwardHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags | UInt32(shiftKey),
            reverseHotKeyID,
            GetApplicationEventTarget(),
            0,
            &reverseHotKeyRef
        )
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let reverseHotKeyRef {
            UnregisterEventHotKey(reverseHotKeyRef)
            self.reverseHotKeyRef = nil
        }
    }
}
