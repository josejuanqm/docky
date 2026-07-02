//
//  WidgetCatalog.swift
//  Docky
//

import Foundation

enum WidgetOwnerBundleIdentifiers {
    static let calendar = "com.apple.iCal"
    static let reminders = "com.apple.reminders"
    static let batteries = "gt.quintero.Docky.batteries"
    static let systemStatus = "gt.quintero.Docky.system-status"
    static let weather = "gt.quintero.Docky.weather"
    static let genericNowPlaying = "gt.quintero.Docky.now-playing"
    static let search = "gt.quintero.Docky.search"
    static let photoFrame = "gt.quintero.Docky.photo-frame"
}

struct WidgetRegistration: Equatable, Identifiable {
    let kind: WidgetKind
    let ownerBundleIdentifier: String
    let defaultSpan: TileSpan
    let includesInPalette: Bool
    let includesInSmartStack: Bool

    var id: String {
        "\(ownerBundleIdentifier):\(kind.rawValue)"
    }

    func makeTile(span: TileSpan? = nil) -> WidgetTile {
        WidgetTile(
            identifier: id,
            title: kind.title,
            kind: kind,
            ownerBundleIdentifier: ownerBundleIdentifier,
            span: span ?? defaultSpan
        )
    }
}

enum WidgetCatalog {
    static let calendar = WidgetRegistration(
        kind: .calendar,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.calendar,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: true
    )

    static let reminders = WidgetRegistration(
        kind: .reminders,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.reminders,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: true
    )

    static let calendarDate = WidgetRegistration(
        kind: .calendarDate,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.calendar,
        defaultSpan: .one,
        includesInPalette: false,
        includesInSmartStack: false
    )

    static let batteries = WidgetRegistration(
        kind: .batteries,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.batteries,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: true
    )

    static let systemStatus = WidgetRegistration(
        kind: .systemStatus,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.systemStatus,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: true
    )

    static let weather = WidgetRegistration(
        kind: .weather,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.weather,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: true
    )

    static let genericNowPlaying = WidgetRegistration(
        kind: .nowPlaying,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.genericNowPlaying,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: false
    )

    static let search = WidgetRegistration(
        kind: .search,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.search,
        defaultSpan: .two,
        // Theme-only widget: kept out of the dock editor palette so
        // it can't be dragged in manually. Themes can still inject it
        // via `layout.insertions` when widget injection lands.
        includesInPalette: false,
        includesInSmartStack: false
    )

    static let photoFrame = WidgetRegistration(
        kind: .photoFrame,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.photoFrame,
        defaultSpan: .two,
        includesInPalette: true,
        includesInSmartStack: false
    )

    static let builtInRegistrations: [WidgetRegistration] = [
        calendar,
        calendarDate,
        reminders,
        batteries,
        systemStatus,
        weather,
        genericNowPlaying,
        search,
        photoFrame,
    ]

    /// All available widget registrations, built-ins plus any external
    /// bundles that ExternalWidgetLoader has registered. Computed (not
    /// cached) so registrations discovered after first access still show
    /// up the next time the palette refreshes.
    static var staticRegistrations: [WidgetRegistration] {
        builtInRegistrations + externalRegistrations()
    }

    static var paletteRegistrations: [WidgetRegistration] {
        staticRegistrations.filter(\.includesInPalette)
    }

    static var smartStackRegistrations: [WidgetRegistration] {
        staticRegistrations.filter(\.includesInSmartStack)
    }

    private static func externalRegistrations() -> [WidgetRegistration] {
        ExternalWidgetRegistry.shared.registrations.map { registration in
            let metadata = registration.metadata
            return WidgetRegistration(
                kind: .external(metadata.identifier),
                ownerBundleIdentifier: metadata.identifier,
                defaultSpan: metadata.defaultSpan,
                includesInPalette: metadata.includesInPalette,
                includesInSmartStack: metadata.includesInSmartStack
            )
        }
    }

    /// Owner bundle identifiers that are *visible* in a freshly-inserted
    /// smart stack by default. Anything in `smartStackRegistrations`
    /// outside this set is hidden until the user toggles it on.
    /// Now-Playing widgets are discovered dynamically and aren't part
    /// of `smartStackRegistrations`, so they appear automatically as
    /// soon as a supported media app starts playing.
    static let defaultVisibleSmartStackOwnerBundleIdentifiers: Set<String> = [
        WidgetOwnerBundleIdentifiers.calendar,
        WidgetOwnerBundleIdentifiers.weather,
    ]

    /// Materialized "hidden" list — the inverse of
    /// `defaultVisibleSmartStackOwnerBundleIdentifiers` — formatted as
    /// the `hiddenWidgetOwnerBundleIdentifiers` argument the
    /// persistence layer expects when creating a new smart stack item.
    static let defaultHiddenSmartStackOwnerBundleIdentifiers: [String] =
        smartStackRegistrations
            .map(\.ownerBundleIdentifier)
            .filter { !defaultVisibleSmartStackOwnerBundleIdentifiers.contains($0) }
}
