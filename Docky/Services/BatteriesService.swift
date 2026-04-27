//
//  BatteriesService.swift
//  Docky
//

import AppKit
import Combine
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps

final class BatteriesService: ObservableObject {
    static let shared = BatteriesService()

    @Published private(set) var snapshot: BatteriesSnapshot?
    @Published private(set) var isLoading = false

    private var lastRefreshDate: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        subscribeToRefreshTimer()
        subscribeToWakeNotifications()
    }

    func ensureFreshBatteries() {
        refresh(force: false)
    }

    func refresh(force: Bool) {
        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < 60 {
            return
        }

        loadSnapshot()
    }

    func openInBatterySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func subscribeToRefreshTimer() {
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh(force: true)
            }
            .store(in: &cancellables)
    }

    private func subscribeToWakeNotifications() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.refresh(force: true)
            }
            .store(in: &cancellables)
    }

    private func loadSnapshot() {
        isLoading = true

        let productNamesByLocationID = Self.hidProductNamesByLocationID()
        let devices = [Self.loadInternalBatterySnapshot()].compactMap { $0 }
            + Self.loadAccessoryBatterySnapshots(productNamesByLocationID: productNamesByLocationID)

        let sortedDevices = devices.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortRank < rhs.kind.sortRank
            }

            if lhs.minimumPercentage != rhs.minimumPercentage {
                return (lhs.minimumPercentage ?? 101) < (rhs.minimumPercentage ?? 101)
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        snapshot = sortedDevices.isEmpty ? nil : BatteriesSnapshot(devices: sortedDevices)
        lastRefreshDate = Date()
        isLoading = false
    }

    private static func loadInternalBatterySnapshot() -> BatteryDeviceSnapshot? {
        let powerSourcesInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo).takeRetainedValue() as Array

        for powerSource in powerSources {
            guard let description = IOPSGetPowerSourceDescription(powerSourcesInfo, powerSource)?.takeUnretainedValue() as? [String: Any],
                  let powerSourceType = description[kIOPSTypeKey as String] as? String,
                  powerSourceType == kIOPSInternalBatteryType as String,
                  (description[kIOPSIsPresentKey as String] as? Bool) != false,
                  let currentCapacity = numberValue(description[kIOPSCurrentCapacityKey as String]),
                  let maxCapacity = numberValue(description[kIOPSMaxCapacityKey as String]),
                  maxCapacity > 0 else {
                continue
            }

            let percentage = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
            let isCharging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false
            let powerSourceState = description[kIOPSPowerSourceStateKey as String] as? String
            let timeToEmpty = numberValue(description[kIOPSTimeToEmptyKey as String])
            let timeToFull = numberValue(description[kIOPSTimeToFullChargeKey as String])

            return BatteryDeviceSnapshot(
                id: "internal-battery",
                name: "Mac",
                kind: .mac,
                transport: nil,
                isCharging: isCharging,
                levels: [BatteryLevelSnapshot(component: .main, percentage: percentage)],
                powerStateDescription: internalPowerStateDescription(
                    isCharging: isCharging,
                    powerSourceState: powerSourceState,
                    timeToEmpty: timeToEmpty,
                    timeToFull: timeToFull
                )
            )
        }

        return nil
    }

    private static func loadAccessoryBatterySnapshots(productNamesByLocationID: [UInt32: String]) -> [BatteryDeviceSnapshot] {
        let matching = IOServiceMatching("IOService") as NSMutableDictionary
        matching[kIOPropertyMatchKey] = ["HasBattery": true] as NSDictionary

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [BatteryDeviceSnapshot] = []
        var seenIdentifiers = Set<String>()

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else {
                break
            }
            defer { IOObjectRelease(service) }

            guard let properties = registryProperties(for: service),
                  (properties["Built-In"] as? Bool) != true else {
                continue
            }

            let levels = batteryLevels(from: properties)
            guard !levels.isEmpty else {
                continue
            }

            let locationID = uint32Value(properties["LocationID"])
            let resolvedName = locationID.flatMap { productNamesByLocationID[$0] }
                ?? trimmedNonEmptyString(properties["Product"])
                ?? inferredAccessoryName(from: properties)
            let identifier = accessoryIdentifier(
                locationID: locationID,
                properties: properties,
                fallbackName: resolvedName
            )

            guard seenIdentifiers.insert(identifier).inserted else {
                continue
            }

            devices.append(BatteryDeviceSnapshot(
                id: identifier,
                name: resolvedName,
                kind: accessoryKind(for: resolvedName, properties: properties),
                transport: trimmedNonEmptyString(properties["Transport"]),
                isCharging: false,
                levels: levels,
                powerStateDescription: nil
            ))
        }

        return devices
    }

    private static func hidProductNamesByLocationID() -> [UInt32: String] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        let deviceSet = IOHIDManagerCopyDevices(manager) as NSSet? ?? []
        var productNamesByLocationID: [UInt32: String] = [:]

        for case let device as IOHIDDevice in deviceSet {
            guard let locationID = uint32Value(IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString)),
                  let productName = trimmedNonEmptyString(IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString)) else {
                continue
            }

            productNamesByLocationID[locationID] = productName
        }

        return productNamesByLocationID
    }

    private static func batteryLevels(from properties: [String: Any]) -> [BatteryLevelSnapshot] {
        let candidates: [(String, BatteryLevelSnapshot.Component)] = [
            ("BatteryPercent", .main),
            ("BatteryPercentLeft", .left),
            ("BatteryPercentRight", .right),
            ("BatteryPercentCase", .caseBattery),
        ]

        return candidates.compactMap { key, component in
            guard let percentage = boundedPercentage(properties[key]) else {
                return nil
            }

            return BatteryLevelSnapshot(component: component, percentage: percentage)
        }
    }

    private static func internalPowerStateDescription(
        isCharging: Bool,
        powerSourceState: String?,
        timeToEmpty: Int?,
        timeToFull: Int?
    ) -> String? {
        if isCharging {
            if let timeToFull, timeToFull > 0 {
                return "Charging • \(durationText(minutes: timeToFull)) until full"
            }

            return "Charging"
        }

        if powerSourceState == kIOPSACPowerValue as String {
            return "On power"
        }

        if let timeToEmpty, timeToEmpty > 0 {
            return "\(durationText(minutes: timeToEmpty)) remaining"
        }

        if powerSourceState == kIOPSBatteryPowerValue as String {
            return "On battery"
        }

        return nil
    }

    private static func inferredAccessoryName(from properties: [String: Any]) -> String {
        if let notificationType = trimmedNonEmptyString(properties["ConnectionNotificationType"]) {
            if notificationType.hasPrefix("KB") {
                return "Keyboard"
            }

            if notificationType.hasPrefix("TP") {
                return "Trackpad"
            }

            if notificationType.hasPrefix("M") {
                return "Mouse"
            }
        }

        if let ioClass = trimmedNonEmptyString(properties["IOClass"])?.lowercased() {
            if ioClass.contains("keyboard") {
                return "Keyboard"
            }

            if ioClass.contains("trackpad") {
                return "Trackpad"
            }

            if ioClass.contains("mouse") {
                return "Mouse"
            }
        }

        return "Accessory"
    }

    private static func accessoryKind(for name: String, properties: [String: Any]) -> BatteryDeviceSnapshot.Kind {
        let normalizedName = name.lowercased()
        if normalizedName.contains("keyboard") {
            return .keyboard
        }

        if normalizedName.contains("trackpad") {
            return .trackpad
        }

        if normalizedName.contains("mouse") {
            return .mouse
        }

        if normalizedName.contains("airpods") || normalizedName.contains("beats") || normalizedName.contains("headphone") {
            return .headphones
        }

        if let transport = trimmedNonEmptyString(properties["Transport"]),
           transport == "Bluetooth" {
            return .accessory
        }

        return .accessory
    }

    private static func accessoryIdentifier(
        locationID: UInt32?,
        properties: [String: Any],
        fallbackName: String
    ) -> String {
        if let locationID {
            return "battery-accessory-location-\(locationID)"
        }

        if let address = trimmedNonEmptyString(properties["DeviceAddress"]) {
            return "battery-accessory-address-\(address)"
        }

        if let serialNumber = trimmedNonEmptyString(properties["SerialNumber"]) {
            return "battery-accessory-serial-\(serialNumber)"
        }

        return "battery-accessory-\(fallbackName.replacingOccurrences(of: " ", with: "-").lowercased())"
    }

    private static func registryProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var propertiesRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = propertiesRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return properties
    }

    private static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return "\(remainingMinutes)m"
        }

        if remainingMinutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(remainingMinutes)m"
    }

    private static func boundedPercentage(_ value: Any?) -> Int? {
        guard let value = numberValue(value) else {
            return nil
        }

        return max(0, min(100, value))
    }

    private static func numberValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let value as Int:
            return value
        default:
            return nil
        }
    }

    private static func uint32Value(_ value: Any?) -> UInt32? {
        switch value {
        case let number as NSNumber:
            return number.uint32Value
        case let value as UInt32:
            return value
        case let value as UInt64:
            return UInt32(clamping: value)
        case let value as Int:
            return UInt32(clamping: value)
        default:
            return nil
        }
    }

    private static func trimmedNonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct BatteriesSnapshot: Equatable {
    let devices: [BatteryDeviceSnapshot]

    var isEmpty: Bool {
        devices.isEmpty
    }

    var primaryDevice: BatteryDeviceSnapshot? {
        internalBattery ?? accessoryDevices.first
    }

    var internalBattery: BatteryDeviceSnapshot? {
        devices.first(where: { $0.kind == .mac })
    }

    var accessoryDevices: [BatteryDeviceSnapshot] {
        devices.filter { $0.kind != .mac }
    }

    var lowestPercentage: Int? {
        devices.compactMap(\.minimumPercentage).min()
    }
}

struct BatteryDeviceSnapshot: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case mac
        case keyboard
        case trackpad
        case mouse
        case headphones
        case accessory

        fileprivate var sortRank: Int {
            switch self {
            case .mac:
                0
            case .keyboard:
                1
            case .trackpad:
                2
            case .mouse:
                3
            case .headphones:
                4
            case .accessory:
                5
            }
        }
    }

    let id: String
    let name: String
    let kind: Kind
    let transport: String?
    let isCharging: Bool
    let levels: [BatteryLevelSnapshot]
    let powerStateDescription: String?

    var primaryPercentage: Int? {
        if let mainLevel = levels.first(where: { $0.component == .main }) {
            return mainLevel.percentage
        }

        guard !levels.isEmpty else {
            return nil
        }

        return Int((Double(levels.map(\.percentage).reduce(0, +)) / Double(levels.count)).rounded())
    }

    var minimumPercentage: Int? {
        levels.map(\.percentage).min()
    }
}

struct BatteryLevelSnapshot: Identifiable, Equatable {
    enum Component: String, Equatable {
        case main
        case left
        case right
        case caseBattery

        var id: String { rawValue }

        var shortLabel: String? {
            switch self {
            case .main:
                nil
            case .left:
                "L"
            case .right:
                "R"
            case .caseBattery:
                "C"
            }
        }
    }

    let component: Component
    let percentage: Int

    var id: String {
        component.id
    }
}
