//
//  DockSettingsService.swift
//  Docky
//
//  Reads system Dock preferences (com.apple.dock) and republishes them.
//
//  Reads from `CFPreferences` on `com.apple.dock`.
//

import AppKit
import Combine

final class DockSettingsService: ObservableObject {
    static let shared = DockSettingsService()

    enum Orientation: String {
        case bottom, left, right
    }

    enum MinimizeEffect: String {
        case genie, scale, suck
    }

    @Published private(set) var orientation: Orientation = .bottom
    @Published private(set) var tileSize: CGFloat = 48
    @Published private(set) var largeSize: CGFloat = 64
    @Published private(set) var magnification: Bool = false
    @Published private(set) var autohide: Bool = false
    @Published private(set) var autohideDelay: TimeInterval = 0.5
    @Published private(set) var autohideTimeModifier: Double = 1.0
    @Published private(set) var minimizeEffect: MinimizeEffect = .genie
    @Published private(set) var minimizeToApplication: Bool = false
    @Published private(set) var showRecents: Bool = true
    @Published private(set) var showProcessIndicators: Bool = true

    var displayTileSize: CGFloat {
        magnification ? max(tileSize, largeSize) : tileSize
    }

    private init() {
        refresh()
    }

    func refresh() {
        guard let values = DockPlistReader.read() else { return }
        applyValues(values)
    }

    func setTileSize(_ size: CGFloat) {
        tileSize = size
    }

    func setLargeSize(_ size: CGFloat) {
        largeSize = size
    }

    func setMagnification(_ isEnabled: Bool) {
        magnification = isEnabled
    }

    private func applyValues(_ values: [String: Any]) {
        if let raw = values["orientation"] as? String, let value = Orientation(rawValue: raw) {
            orientation = value
        }
        if let value = (values["tilesize"] as? NSNumber)?.doubleValue {
            tileSize = CGFloat(value)
        }
        if let value = (values["largesize"] as? NSNumber)?.doubleValue {
            largeSize = CGFloat(value)
        }
        if let value = (values["magnification"] as? NSNumber)?.boolValue {
            magnification = value
        }
        if let value = (values["autohide"] as? NSNumber)?.boolValue {
            autohide = value
        }
        if let value = (values["autohide-delay"] as? NSNumber)?.doubleValue {
            autohideDelay = value
        }
        if let value = (values["autohide-time-modifier"] as? NSNumber)?.doubleValue {
            autohideTimeModifier = value
        }
        if let raw = values["mineffect"] as? String, let value = MinimizeEffect(rawValue: raw) {
            minimizeEffect = value
        }
        if let value = (values["minimize-to-application"] as? NSNumber)?.boolValue {
            minimizeToApplication = value
        }
        if let value = (values["show-recents"] as? NSNumber)?.boolValue {
            showRecents = value
        }
        if let value = (values["show-process-indicators"] as? NSNumber)?.boolValue {
            showProcessIndicators = value
        }
    }

}
