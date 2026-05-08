//
//  PermissionsView.swift
//  Docky
//

import AppKit
import AVKit
import SwiftUI

private struct PermissionsWindowFramePreference: Equatable {
    let frame: CGRect
    let layoutKey: String
}

private struct PermissionsWindowFramePreferenceKey: PreferenceKey {
    static var defaultValue = PermissionsWindowFramePreference(frame: .zero, layoutKey: "")

    static func reduce(value: inout PermissionsWindowFramePreference, nextValue: () -> PermissionsWindowFramePreference) {
        value = nextValue()
    }
}

struct PermissionsView: View {
    @ObservedObject private var service = PermissionsService.shared
    @State private var currentIndex = 0
    @State private var isDismissing = false

    let steps: [Permission]
    let topBarAdjustment: CGFloat
    let onWindowFrameChange: (CGRect) -> Void
    let onOpenSystemSettings: (Permission) -> Void
    let onComplete: () -> Void

    private var step: Permission { steps[currentIndex] }
    private var status: PermissionStatus { service.status(for: step) }
    private var isLastStep: Bool { currentIndex == steps.count - 1 }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        cardView
        .padding(.top, topBarAdjustment)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: PermissionsWindowFramePreferenceKey.self,
                        value: PermissionsWindowFramePreference(
                            frame: proxy.frame(in: .local),
                            layoutKey: "\(currentIndex)-\(statusLabel)"
                        )
                    )
            }
        )
        .onAppear {
            service.refresh()
        }
        .onPreferenceChange(PermissionsWindowFramePreferenceKey.self) { preference in
            guard !preference.frame.isEmpty else { return }
            onWindowFrameChange(preference.frame)
        }
        .task(id: currentIndex) {
            if (step == .finderAutomation || step == .location), status == .notDetermined {
                _ = await service.requestPermission(for: step)
            }

            if step == .systemEventsAutomation,
               status == .notDetermined,
               service.status(for: .accessibility) == .granted {
                _ = await service.requestPermission(for: step)
            }

            await pollUntilAdvance()
        }
    }

    private var cardView: some View {
        VStack(spacing: 0) {
            topSection
            bottomSection
        }
        .frame(width: 760)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12))
        )
        .overlay(alignment: .topLeading) {
            quitButton
                .padding(18)
        }
        .overlay(alignment: .topTrailing) {
            skipButton
                .padding(18)
        }
    }

    private var topSection: some View {
        mediaArtwork
        .frame(height: 316)
    }

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome to Docky")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(step.title)
                    .font(.system(size: 34, weight: .bold))

                Text(step.explanation)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                PageDots(totalPages: steps.count, currentIndex: currentIndex)
            }

            if showsAppDragProxy {
                draggableAppProxy
            }

            grantActions

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 30)
        .background(Color.clear)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var mediaArtwork: some View {
        ZStack(alignment: .topLeading) {
            if let mediaResourceName {
                LoopingVideoView(resourceName: mediaResourceName, fileExtension: "mp4")
            } else {
                fallbackMediaSurface
            }
        }
    }

    private var fallbackMediaSurface: some View {
        ZStack(alignment: .bottomLeading) {
            Color(nsColor: .controlBackgroundColor)

            HStack(alignment: .bottom, spacing: 18) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: dockyAppURL.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.black.opacity(0.18), radius: 16, y: 10)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Docky Setup", systemImage: "sparkles.rectangle.stack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(mediaCaption)
                        .font(.system(size: 24, weight: .semibold))
                }

                Spacer()

                Image(systemName: stepSymbolName)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 84, height: 84)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.12))
                    )
            }
            .padding(22)
        }
    }

    private var cardBackground: some ShapeStyle {
        Color(nsColor: .windowBackgroundColor)
    }

    private func dismissOnboarding() {
        guard !isDismissing else { return }
        isDismissing = true
        onComplete()
    }

    private func openSystemSettings() {
        onOpenSystemSettings(step)
    }

    @ViewBuilder
    private var grantActions: some View {
        HStack(spacing: 12) {
            Button(systemSettingsButtonTitle) {
                openSystemSettings()
            }
            .onboardingButtonStyle()

            if step == .finderAutomation || step == .systemEventsAutomation || step == .screenCapture || step == .location {
                requestButton
            }
        }
    }

    private var showsAppDragProxy: Bool {
        step != .finderAutomation && step != .systemEventsAutomation && step != .location
    }

    private var draggableAppProxy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag Docky into the list in System Settings to add it without searching.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: dockyAppURL.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Docky.app")
                        .font(.headline)
                    Text("Drag this into the macOS privacy list")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "hand.draw")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15))
            )
            .onDrag {
                NSItemProvider(object: dockyAppURL as NSURL)
            }
        }
        .padding(.top, 4)
    }

    private var dockyAppURL: URL {
        Bundle.main.bundleURL
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Re-check") { service.refresh() }
                .onboardingButtonStyle()

            Spacer()

            if status == .granted {
                Button(primaryActionTitle) { advance() }
                    .keyboardShortcut(.return)
                    .onboardingButtonStyle()
            }
        }
    }

    private var skipButton: some View {
        Button("Skip") { skipCurrentStep() }
            .buttonStyle(.plain)
            .padding(9)
            .background(Color(nsColor: .controlBackgroundColor), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.12)))
    }

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: Circle())
        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.12)))
    }

    private var grantMethodLabel: String? {
        switch grantMethod {
        case .fullDiskAccess: return "Full Disk Access"
        case .automation: return "Automation"
        case .accessibility: return "Accessibility"
        case .screenCapture: return "Screen Recording"
        case .location: return "Location"
        case .none: return nil
        }
    }

    @ViewBuilder
    private var requestButton: some View {
        if step == .finderAutomation || step == .systemEventsAutomation || step == .screenCapture || step == .location {
            Button(requestButtonTitle) {
                Task {
                    _ = await service.requestPermission(for: step)
                }
            }
            .onboardingButtonStyle()
        }
    }

    private var grantMethod: GrantMethod? {
        switch step {
        case .userFolders:
            return service.userFoldersGrantMethod
        case .finderAutomation:
            return service.finderAutomationGrantMethod
        case .accessibility:
            return service.accessibilityGrantMethod
        case .systemEventsAutomation:
            return service.systemEventsAutomationGrantMethod
        case .screenCapture:
            return service.screenCaptureGrantMethod
        case .location:
            return service.locationGrantMethod
        }
    }

    private var systemSettingsButtonTitle: String {
        switch step {
        case .finderAutomation:
            return "Open System Settings (Automation)"
        case .systemEventsAutomation:
            return "Open System Settings (Automation)"
        case .userFolders:
            return "Open System Settings (Full Disk Access)"
        case .accessibility:
            return "Open System Settings (Accessibility)"
        case .screenCapture:
            return "Open System Settings (Screen Recording)"
        case .location:
            return "Open System Settings (Location Services)"
        }
    }

    private var requestButtonTitle: String {
        switch step {
        case .finderAutomation:
            return "Request Finder Access"
        case .systemEventsAutomation:
            return "Request System Events Access"
        case .screenCapture:
            return "Request Screen Recording Access"
        case .location:
            return "Request Location Access"
        case .userFolders, .accessibility:
            return "Request Access"
        }
    }

    private var statusIcon: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        case .notDetermined: return "circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .secondary
        }
    }

    private var primaryActionTitle: String {
        isLastStep ? "Continue" : "Next"
    }

    private func advance() {
        if isLastStep {
            dismissOnboarding()
        } else {
            currentIndex += 1
            openNextStepSystemSettings()
        }
    }

    private func skipCurrentStep() {
        service.markPermissionSkipped(step)
        advance()
    }

    private func openNextStepSystemSettings() {
        guard !isDismissing else { return }

        let nextStep = step
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !isDismissing, self.step == nextStep else { return }
            onOpenSystemSettings(nextStep)
        }
    }

    private func advanceIfReady() {
        guard status == .granted else { return }
        advance()
    }

    private func pollUntilAdvance() async {
        advanceIfReady()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            service.refresh()
            if status == .granted {
                advance()
                return
            }
        }
    }

    private var heroGradient: [Color] {
        switch step {
        case .userFolders:
            return [Color(red: 0.29, green: 0.46, blue: 0.96), Color(red: 0.15, green: 0.14, blue: 0.48)]
        case .finderAutomation:
            return [Color(red: 0.27, green: 0.68, blue: 0.98), Color(red: 0.12, green: 0.31, blue: 0.68)]
        case .accessibility:
            return [Color(red: 0.66, green: 0.39, blue: 0.98), Color(red: 0.24, green: 0.14, blue: 0.56)]
        case .systemEventsAutomation:
            return [Color(red: 0.98, green: 0.69, blue: 0.24), Color(red: 0.58, green: 0.34, blue: 0.08)]
        case .screenCapture:
            return [Color(red: 0.10, green: 0.70, blue: 0.63), Color(red: 0.07, green: 0.28, blue: 0.45)]
        case .location:
            return [Color(red: 1.00, green: 0.53, blue: 0.40), Color(red: 0.60, green: 0.19, blue: 0.21)]
        }
    }

    private var stepSymbolName: String {
        switch step {
        case .userFolders:
            return "folder.badge.gearshape"
        case .finderAutomation:
            return "folder.badge.gearshape"
        case .accessibility:
            return "figure.wave.circle"
        case .systemEventsAutomation:
            return "keyboard"
        case .screenCapture:
            return "rectangle.on.rectangle"
        case .location:
            return "location.circle"
        }
    }

    private var stepSummary: String {
        switch status {
        case .granted:
            return "This permission is already enabled. You can continue when ready."
        case .denied:
            return "macOS has this disabled right now. Open System Settings, enable it, then come back and re-check."
        case .notDetermined:
            return "Docky will guide you through the fastest way to enable this on your Mac."
        }
    }

    private var mediaCaption: String {
        switch step {
        case .userFolders:
            return "Preview pinned folders instantly"
        case .finderAutomation:
            return "Reveal and manage files in Finder"
        case .accessibility:
            return "Control interface actions smoothly"
        case .systemEventsAutomation:
            return "Run curated menu actions quickly"
        case .screenCapture:
            return "Capture live window previews"
        case .location:
            return "Show local weather in the dock"
        }
    }

    private var mediaResourceName: String? {
        switch step {
        case .userFolders:
            return "folder-preview"
        case .finderAutomation:
            return "trash"
        case .accessibility:
            return "window-switching"
        case .systemEventsAutomation:
            return "automation"
        case .screenCapture:
            return "window-switching"
        case .location:
            return nil
        }
    }

    private var bottomSummary: String {
        if step == .finderAutomation {
            return "Finder access can be requested here now, so reveal-in-Finder and Trash actions work without waiting for the first macOS prompt."
        }

        if step == .systemEventsAutomation {
            return "System Events access can be requested here now for curated menu-click actions. Accessibility should be enabled too, since UI scripting depends on both permissions."
        }

        if step.isRequiredAtLaunch {
            return "This permission unlocks a core Docky feature, but you can skip it for now and grant it later."
        }

        return "This permission unlocks an optional feature and can be granted later from Settings."
    }

    private var statusBadge: some View {
        Label(statusLabel, systemImage: statusIcon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(statusBadgeColor.opacity(0.28), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.16))
            )
    }

    private var statusLabel: String {
        switch status {
        case .granted:
            return "Granted"
        case .denied:
            return "Needs Attention"
        case .notDetermined:
            return "Not Yet Granted"
        }
    }

    private var statusBadgeColor: Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .orange
        case .notDetermined:
            return .white
        }
    }
}

private final class LoopingPlayerView: NSView {
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    private var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer backing layer")
        }
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
    }

    override func layout() {
        super.layout()
        updateVideoRect()
    }

    func configure(url: URL?) {
        guard currentURL != url else { return }
        currentURL = url

        guard let url else {
            playerLayer.player = nil
            queuePlayer = nil
            looper = nil
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        playerLayer.player = player
        player.play()
    }

    private func updateVideoRect() {
        guard let presentationSize = playerLayer.player?.currentItem?.presentationSize,
              presentationSize.width > 0,
              presentationSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            playerLayer.frame = bounds
            return
        }

        let scale = max(bounds.width / presentationSize.width, bounds.height / presentationSize.height)
        let size = CGSize(width: presentationSize.width * scale, height: presentationSize.height * scale)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: 0)
        playerLayer.frame = CGRect(origin: origin, size: size)
    }
}

private struct LoopingVideoView: NSViewRepresentable {
    let resourceName: String
    let fileExtension: String

    func makeNSView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.configure(url: mediaURL)
        return view
    }

    func updateNSView(_ nsView: LoopingPlayerView, context: Context) {
        nsView.configure(url: mediaURL)
    }

    private var mediaURL: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: fileExtension)
    }
}

private struct PageDots: View {
    let totalPages: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentIndex ? Color.accentColor : Color.secondary.opacity(0.30))
                    .frame(width: index == currentIndex ? 24 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentIndex + 1) of \(max(totalPages, 1))")
    }
}

private extension View {
    func onboardingButtonStyle() -> some View {
        buttonStyle(.bordered)
            .controlSize(.large)
    }
}
