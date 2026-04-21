//
//  MediaPlaybackService.swift
//  Docky
//

import AppKit
import Combine
import Foundation
import OSLog

struct MediaPlaybackState: Equatable {
    let bundleIdentifier: String
    let displayName: String
    var title: String
    var artist: String
    var album: String
    var currentTime: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
    var isAvailable: Bool
    var supportsFavorite: Bool
    var isFavorite: Bool
    var artworkData: Data?
    var lastUpdated: Date

    var hasContent: Bool {
        !title.isEmpty || !artist.isEmpty || artworkData != nil
    }

    var estimatedCurrentTime: TimeInterval {
        guard isPlaying, duration > 0 else {
            return min(max(currentTime, 0), duration)
        }

        let elapsed = Date().timeIntervalSince(lastUpdated)
        return min(max(currentTime + elapsed, 0), duration)
    }
}

final class MediaPlaybackService: ObservableObject {
    static let shared = MediaPlaybackService()

    @Published private(set) var statesByBundleIdentifier: [String: MediaPlaybackState] = [:]

    private let mediaRemote = MediaRemoteBridge.shared

    private init() {
        mediaRemote.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.apply(state)
            }
        }

        // Avoid re-entrant work while `shared` is still being initialized.
        DispatchQueue.main.async { [weak self] in
            self?.activate()
        }
    }

    private func activate() {
        mediaRemote.start()
    }

    func supportsWidget(bundleIdentifier: String) -> Bool {
        !bundleIdentifier.isEmpty
    }

    func state(for bundleIdentifier: String) -> MediaPlaybackState? {
        statesByBundleIdentifier[bundleIdentifier]
    }

    func refresh() {
        mediaRemote.start()
    }

    func togglePlayPause(for bundleIdentifier: String) async {
        guard let currentState = state(for: bundleIdentifier), currentState.hasContent else {
            return
        }

        var updatedState = currentState
        updatedState.isPlaying.toggle()
        updatedState.lastUpdated = Date()
        statesByBundleIdentifier[bundleIdentifier] = updatedState

        mediaRemote.sendCommand(.togglePlayPause)
        try? await Task.sleep(for: .milliseconds(120))
        refresh()
    }

    func skipToNext(for bundleIdentifier: String) async {
        guard state(for: bundleIdentifier)?.hasContent == true else {
            return
        }

        mediaRemote.sendCommand(.nextTrack)
        try? await Task.sleep(for: .milliseconds(120))
        refresh()
    }

    func skipToPrevious(for bundleIdentifier: String) async {
        guard state(for: bundleIdentifier)?.hasContent == true else {
            return
        }

        mediaRemote.sendCommand(.previousTrack)
        try? await Task.sleep(for: .milliseconds(120))
        refresh()
    }

    func setFavorite(_ favorite: Bool, for bundleIdentifier: String) async {
        guard bundleIdentifier == "com.apple.Music" else {
            return
        }

        let source = """
        tell application "Music"
            if it is running then
                try
                    set favorited of current track to \(favorite ? "true" : "false")
                end try
            end if
        end tell
        """

        _ = try? AppleScriptService.shared.executeDescriptor(source: source)
        try? await Task.sleep(for: .milliseconds(120))
        refresh()
    }

    private func apply(_ state: MediaPlaybackState?) {
        guard let state else {
            let now = Date()
            statesByBundleIdentifier = statesByBundleIdentifier.mapValues { existingState in
                var updatedState = existingState
                updatedState.isAvailable = false
                updatedState.isPlaying = false
                updatedState.lastUpdated = now
                return updatedState
            }
            return
        }

        statesByBundleIdentifier[state.bundleIdentifier] = state
    }
}

private struct MediaRemoteSnapshot: Decodable {
    let type: String?
    let diff: Bool?
    let payload: Payload

    struct Payload: Decodable {
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedTime: Double?
        let playing: Bool?
        let artworkData: String?
        let artworkMimeType: String?
        let timestamp: String?

        func merged(over base: Self?) -> Self {
            Self(
                bundleIdentifier: bundleIdentifier ?? base?.bundleIdentifier,
                parentApplicationBundleIdentifier: parentApplicationBundleIdentifier ?? base?.parentApplicationBundleIdentifier,
                title: title ?? base?.title,
                artist: artist ?? base?.artist,
                album: album ?? base?.album,
                duration: duration ?? base?.duration,
                elapsedTime: elapsedTime ?? base?.elapsedTime,
                playing: playing ?? base?.playing,
                artworkData: artworkData ?? base?.artworkData,
                artworkMimeType: artworkMimeType ?? base?.artworkMimeType,
                timestamp: timestamp ?? base?.timestamp
            )
        }
    }
}

private final class MediaRemoteBridge {
    enum Command: Int32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    typealias SendCommand = @convention(c) (Int32, AnyObject?) -> Bool

    static let shared = MediaRemoteBridge()

    var onStateChange: ((MediaPlaybackState?) -> Void)?

    private let sendRemoteCommand: SendCommand?
    private let helper = MediaRemoteHelperProcess()
    private var lastPayloadByBundleIdentifier: [String: MediaRemoteSnapshot.Payload] = [:]
    private var lastActiveBundleIdentifier: String?

    private init() {
        let bundleURL = NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        let bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL)
        self.sendRemoteCommand = Self.function(named: "MRMediaRemoteSendCommand", in: bundle)

        helper.onSnapshot = { [weak self] snapshot in
            self?.handle(snapshot)
        }
    }

    func start() {
        helper.startIfNeeded()
    }

    func refresh() {
        helper.startIfNeeded()
    }

    func sendCommand(_ command: Command) {
        _ = sendRemoteCommand?(command.rawValue, nil)
    }

    private func handle(_ snapshot: MediaRemoteSnapshot?) {
        guard let snapshot else {
            onStateChange?(nil)
            return
        }

        let candidateBundleIdentifier = snapshot.payload.parentApplicationBundleIdentifier ?? snapshot.payload.bundleIdentifier
        let basePayload = candidateBundleIdentifier.flatMap { lastPayloadByBundleIdentifier[$0] }
            ?? lastActiveBundleIdentifier.flatMap { lastPayloadByBundleIdentifier[$0] }
        let payload = snapshot.diff == true ? snapshot.payload.merged(over: basePayload) : snapshot.payload
        let bundleIdentifier = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier ?? ""
        let title = payload.title ?? ""
        let artist = payload.artist ?? ""
        let album = payload.album ?? ""
        let duration = payload.duration ?? 0
        let elapsedTime = payload.elapsedTime ?? 0
        let isPlaying = payload.playing ?? false
        let artworkData = payload.artworkData.flatMap { Data(base64Encoded: $0) }

        guard !bundleIdentifier.isEmpty,
              !title.isEmpty || !artist.isEmpty || artworkData != nil else {
            onStateChange?(nil)
            return
        }

        lastPayloadByBundleIdentifier[bundleIdentifier] = payload
        lastActiveBundleIdentifier = bundleIdentifier

        let state = MediaPlaybackState(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName(for: bundleIdentifier),
            title: title,
            artist: artist,
            album: album,
            currentTime: elapsedTime,
            duration: duration,
            isPlaying: isPlaying,
            isAvailable: true,
            supportsFavorite: bundleIdentifier == "com.apple.Music",
            isFavorite: fetchFavorite(bundleIdentifier: bundleIdentifier),
            artworkData: artworkData,
            lastUpdated: Date()
        )
        onStateChange?(state)
    }

    private func fetchFavorite(bundleIdentifier: String) -> Bool {
        guard bundleIdentifier == "com.apple.Music" else {
            return false
        }

        let source = """
        tell application "Music"
            if it is running then
                try
                    return favorited of current track
                on error
                    return false
                end try
            end if
            return false
        end tell
        """

        return (try? AppleScriptService.shared.executeDescriptor(source: source))?.booleanValue ?? false
    }

    private func displayName(for bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return FileManager.default.displayName(atPath: url.path)
        }

        return bundleIdentifier
    }

    private static func function<T>(named name: String, in bundle: CFBundle?) -> T? {
        guard let bundle,
              let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) else {
            return nil
        }

        return unsafeBitCast(pointer, to: T.self)
    }
}

private final class MediaRemoteHelperProcess {
    private static let logger = Logger(subsystem: "gt.quintero.Docky", category: "MediaRemoteHelper")

    var onSnapshot: ((MediaRemoteSnapshot?) -> Void)?

    private var process: Process?
    private var outputPipe: Pipe?
    private var bufferedOutput = Data()

    func startIfNeeded() {
        guard process?.isRunning != true else {
            Self.logger.debug("startIfNeeded skipped; helper already running")
            return
        }

        Self.logger.debug("startIfNeeded beginning helper launch")
        stop()

        guard let launch = resolveLaunchConfiguration() else {
            Self.logger.error("Failed to resolve helper launch configuration")
            return
        }

        Self.logger.debug("Launching helper executable: \(launch.executablePath, privacy: .public)")

        let process = Process()
        let outputPipe = Pipe()
        self.outputPipe = outputPipe
        process.executableURL = URL(fileURLWithPath: launch.executablePath)
        process.arguments = launch.arguments
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        process.terminationHandler = { [weak self] _ in
            Self.logger.debug("Helper terminated")
            DispatchQueue.main.async {
                self?.handleTermination()
            }
        }

        installOutputReader()

        do {
            try process.run()
            self.process = process
            Self.logger.debug("Helper process launched successfully")
        } catch {
            Self.logger.error("Helper process failed to launch: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    private func stop() {
        Self.logger.debug("Stopping helper process")
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        bufferedOutput.removeAll(keepingCapacity: false)
        outputPipe = nil

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
    }

    private func installOutputReader() {
        guard let outputPipe else {
            Self.logger.error("installOutputReader called without output pipe")
            return
        }

        Self.logger.debug("Installing output reader")
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.drainOutput(from: handle)
        }
    }

    private func drainOutput(from handle: FileHandle) {
        let data = handle.availableData
        guard !data.isEmpty else {
            return
        }

        Self.logger.debug("drainOutput received \(data.count) bytes")

        bufferedOutput.append(data)

        while let newline = bufferedOutput.firstIndex(of: 0x0A) {
            let lineData = bufferedOutput.prefix(upTo: newline)
            bufferedOutput.removeSubrange(...newline)

            guard !lineData.isEmpty else {
                continue
            }

            if let text = String(data: lineData, encoding: .utf8) {
                Self.logger.debug("Helper raw line: \(text, privacy: .public)")
            }

            if let snapshot = try? JSONDecoder().decode(MediaRemoteSnapshot.self, from: lineData) {
                let bundleIdentifier = snapshot.payload.parentApplicationBundleIdentifier ?? snapshot.payload.bundleIdentifier ?? ""
                Self.logger.debug("Decoded helper snapshot for \(bundleIdentifier, privacy: .public)")
                onSnapshot?(snapshot)
            } else if let text = String(data: lineData, encoding: .utf8), text == "null" {
                Self.logger.debug("Decoded helper null snapshot")
                onSnapshot?(nil)
            } else if let text = String(data: lineData, encoding: .utf8) {
                Self.logger.error("Failed to decode helper line: \(text, privacy: .public)")
            }
        }
    }

    private func handleTermination() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
    }

    private func resolveLaunchConfiguration() -> HelperLaunchConfiguration? {
        guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") else {
            return nil
        }

        Self.logger.debug("Using bundled MediaRemote adapter")
        return HelperLaunchConfiguration(
            executablePath: "/usr/bin/perl",
            arguments: [scriptURL.path, frameworkPath, "stream"]
        )
    }
}

private struct HelperLaunchConfiguration {
    let executablePath: String
    let arguments: [String]
}
