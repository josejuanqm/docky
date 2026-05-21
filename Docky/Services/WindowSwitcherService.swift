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
    @Published private(set) var windowPreviews: [String: NSImage] = [:]
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

    var resolvedLayout: WindowSwitcherLayout {
        let canCapture = PermissionsService.shared.screenCapture == .granted
        return DockyPreferences.shared.windowSwitcherLayout.resolved(canCaptureThumbnails: canCapture)
    }

    private var activePreviewMode: WindowSwitcherPreviewMode? {
        // Both preview modes are thumbnail-mode features: in-place needs the
        // captured image to show behind the switcher, and instant-focus's
        // "see the real window come forward" UX fights with the list overlay.
        // In list mode the list itself is the preview substitute.
        guard ProductService.shared.isUnlocked(.windowSwitcher),
              DockyPreferences.shared.showsWindowSwitcherFocusPreview,
              resolvedLayout == .thumbnails else {
            return nil
        }

        return DockyPreferences.shared.windowSwitcherPreviewMode
    }

    private var usesInPlacePreview: Bool {
        activePreviewMode == .inPlace
    }

    private var usesInstantFocusPreview: Bool {
        activePreviewMode == .instantFocus
    }

    private init() {
        installHotKeyHandlerIfNeeded()
        registerHotKey(shortcut: DockyPreferences.shared.windowSwitcherShortcut)
        installEventMonitors()
        subscribeToPreferences()
        observeWindowPreviews()
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
        guard ProductService.shared.isUnlocked(.windowSwitcher),
              DockyPreferences.shared.enablesWindowSwitcher else {
            dismiss()
            return
        }

        if isPresented {
            guard !windows.isEmpty else {
                dismiss()
                return
            }

            moveSelection(delta: direction)
            return
        }

        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "switch between windows")
            return
        }

        let latestWindows = WindowRegistry.shared.visible

        windows = latestWindows
        freezeWindowPreviews(for: latestWindows)
        isPresented = true

        if latestWindows.isEmpty {
            // Show the chrome with a "No windows available" message
            // instead of silently no-op'ing — confirming the shortcut
            // worked and there's just nothing to switch to.
            selectedWindowIdentifier = nil
            return
        }

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

        guard !usesInstantFocusPreview else {
            return
        }

        _ = WindowRegistry.shared.focus(selectedWindow)
    }

    func dismiss() {
        cancelFocusedPreview()
        isPresented = false
        isContextMenuPresented = false
        windows = []
        windowPreviews = [:]
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

        if usesInstantFocusPreview {
            cancelFocusedPreview()
            focusSelectedWindowImmediately(identifier: identifier)
            return
        }

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

    func minimizeSelectedWindow() {
        guard let window = selectedWindow else { return }
        if WorkspaceService.shared.minimize(window: window) {
            removeWindow(withIdentifier: window.windowIdentifier)
        }
    }

    func closeSelectedWindow() {
        guard let window = selectedWindow else { return }
        if WorkspaceService.shared.close(window: window) {
            removeWindow(withIdentifier: window.windowIdentifier)
        }
    }

    func zoomSelectedWindow() {
        guard let window = selectedWindow else { return }
        // Bypass WorkspaceService.zoom's focus side-effect: focusing the target
        // window would yank key status from the switcher overlay and break the
        // local key monitor, so subsequent shortcuts would stop working.
        _ = WindowRegistry.shared.zoom(window)
    }

    func removeWindow(withIdentifier identifier: String) {
        guard let removedIndex = windows.firstIndex(where: { $0.windowIdentifier == identifier }) else {
            return
        }

        windows.remove(at: removedIndex)
        windowPreviews.removeValue(forKey: identifier)

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
        observeChanges { [weak self] in
            let shortcut = DockyPreferences.shared.windowSwitcherShortcut
            self?.registerHotKey(shortcut: shortcut)
        }
        .store(in: &cancellables)

        observeChanges { [weak self] in
            let isEnabled = DockyPreferences.shared.enablesWindowSwitcher
            guard let self else { return }
            self.registerHotKey(shortcut: DockyPreferences.shared.windowSwitcherShortcut)
            if !isEnabled {
                self.dismiss()
            }
        }
        .store(in: &cancellables)

        observeChanges { [weak self] in
            _ = DockyPreferences.shared.showsWindowSwitcherFocusPreview
            _ = DockyPreferences.shared.windowSwitcherPreviewMode
            _ = DockyPreferences.shared.windowSwitcherLayout
            self?.refreshSelectionPresentation()
        }
        .store(in: &cancellables)

        PermissionsService.shared.$screenCapture
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSelectionPresentation()
            }
            .store(in: &cancellables)

        PermissionsService.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateGlobalEventMonitors()
            }
            .store(in: &cancellables)

        ProductService.shared.$currentTier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }

                self.registerHotKey(shortcut: DockyPreferences.shared.windowSwitcherShortcut)
                if !ProductService.shared.isUnlocked(.windowSwitcher) {
                    self.dismiss()
                    WindowPreviewWindowController.shared.dismissCurrent()
                }
            }
            .store(in: &cancellables)
    }

    private func observeWindowPreviews() {
        WorkspaceService.shared.$appWindowPreviews
            .receive(on: DispatchQueue.main)
            .sink { [weak self] previews in
                self?.mergeWindowPreviews(previews)
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
                break
            }

            // User-configurable action keys. Navigation cases above take
            // precedence — if a user rebinds an action onto an arrow / Escape /
            // Return key, the built-in nav wins and the action never fires.
            let prefs = DockyPreferences.shared
            switch event.keyCode {
            case prefs.switcherMinimizeKeyCode:
                self.minimizeSelectedWindow()
                return nil
            case prefs.switcherCloseKeyCode:
                self.closeSelectedWindow()
                return nil
            case prefs.switcherZoomKeyCode:
                self.zoomSelectedWindow()
                return nil
            default:
                return event
            }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierReleaseIfNeeded(flags: event.modifierFlags)
            return event
        }

        updateGlobalEventMonitors()
    }

    private func updateGlobalEventMonitors() {
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }

        guard PermissionsService.shared.accessibility == .granted else {
            return
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

    private func freezeWindowPreviews(for windows: [AppWindow]) {
        var previews: [String: NSImage] = [:]

        for window in windows {
            if let preview = WorkspaceService.shared.appWindowPreview(for: window) {
                previews[window.windowIdentifier] = preview
            }
        }

        windowPreviews = previews
    }

    private func mergeWindowPreviews(_ previews: [String: NSImage]) {
        guard isPresented, !windows.isEmpty else {
            return
        }

        var updatedPreviews = windowPreviews
        var didChange = false

        for window in windows {
            guard updatedPreviews[window.windowIdentifier] == nil,
                  let preview = previews[window.windowIdentifier] else {
                continue
            }

            updatedPreviews[window.windowIdentifier] = preview
            didChange = true
        }

        if didChange {
            windowPreviews = updatedPreviews
        }
    }

    func windowPreview(for window: AppWindow) -> NSImage? {
        windowPreviews[window.windowIdentifier]
    }

    private func cancelFocusedPreview() {
        focusedPreviewTask?.cancel()
        focusedPreviewTask = nil
        WorkspaceService.shared.stopLiveFocusPreview()
        focusedPreview = nil
    }

    private func refreshSelectionPresentation() {
        guard let selectedWindowIdentifier else {
            cancelFocusedPreview()
            return
        }

        if usesInstantFocusPreview {
            cancelFocusedPreview()
            focusSelectedWindowImmediately(identifier: selectedWindowIdentifier)
            return
        }

        if usesInPlacePreview {
            scheduleFocusedPreview(forWindowIdentifier: selectedWindowIdentifier)
        } else {
            cancelFocusedPreview()
        }
    }

    private func focusSelectedWindowImmediately(identifier: String) {
        guard isPresented,
              let window = windows.first(where: { $0.windowIdentifier == identifier }) else {
            return
        }

        _ = WindowRegistry.shared.focus(window)
    }

    private func scheduleFocusedPreview(forWindowIdentifier identifier: String) {
        focusedPreviewTask?.cancel()
        focusedPreviewTask = nil

        focusedPreview = nil

        guard usesInPlacePreview,
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
        guard usesInPlacePreview,
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
            guard usesInPlacePreview,
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

        guard ProductService.shared.isUnlocked(.windowSwitcher),
              DockyPreferences.shared.enablesWindowSwitcher,
              shortcut.isValid else {
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
