//
//  SystemStatusService.swift
//  Docky
//

import AppKit
import Combine
import Darwin
import Foundation

final class SystemStatusService: ObservableObject {
    static let shared = SystemStatusService()
    static let activityMonitorBundleIdentifier = "com.apple.ActivityMonitor"

    @Published private(set) var snapshot: SystemStatusSnapshot?
    @Published private(set) var isLoading = false

    private var lastRefreshDate: Date?
    private var previousCPUSample: CPUSample?
    private var previousNetworkCounters: NetworkCounters?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        subscribeToRefreshTimer()
        subscribeToWakeNotifications()
    }

    func ensureFreshStatus() {
        refresh(force: false)
    }

    func refresh(force: Bool) {
        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < 1.5 {
            return
        }

        loadSnapshot()
    }

    func openInActivityMonitor() {
        WorkspaceService.shared.activateOrOpen(bundleIdentifier: Self.activityMonitorBundleIdentifier)
    }

    private func subscribeToRefreshTimer() {
        Timer.publish(every: 2, on: .main, in: .common)
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
        let now = Date()

        let cpuSample = Self.loadCPUSample()
        let memorySample = Self.loadMemorySample()
        let networkCounters = Self.loadNetworkCounters(at: now)

        let cpuUsagePercent = if let cpuSample, let previousCPUSample {
            Self.cpuUsagePercent(from: previousCPUSample, to: cpuSample)
        } else {
            0.0
        }

        let networkThroughput = if let networkCounters, let previousNetworkCounters {
            Self.networkThroughput(from: previousNetworkCounters, to: networkCounters)
        } else {
            NetworkThroughput.zero
        }

        if let cpuSample {
            previousCPUSample = cpuSample
        }

        if let networkCounters {
            previousNetworkCounters = networkCounters
        }

        if let memorySample {
            snapshot = SystemStatusSnapshot(
                cpuUsagePercent: cpuUsagePercent,
                memoryUsagePercent: memorySample.usagePercent,
                usedMemoryBytes: memorySample.usedBytes,
                totalMemoryBytes: memorySample.totalBytes,
                receivedBytesPerSecond: networkThroughput.receivedBytesPerSecond,
                sentBytesPerSecond: networkThroughput.sentBytesPerSecond
            )
        } else {
            snapshot = nil
        }

        lastRefreshDate = now
        isLoading = false
    }

    private static func loadCPUSample() -> CPUSample? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return CPUSample(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private static func cpuUsagePercent(from previous: CPUSample, to current: CPUSample) -> Double {
        let userDelta = current.user &- previous.user
        let systemDelta = current.system &- previous.system
        let idleDelta = current.idle &- previous.idle
        let niceDelta = current.nice &- previous.nice
        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta

        guard totalDelta > 0 else {
            return 0
        }

        let busyDelta = userDelta + systemDelta + niceDelta
        return min(100, max(0, Double(busyDelta) / Double(totalDelta) * 100))
    }

    private static func loadMemorySample() -> MemorySample? {
        var totalMemoryBytes: UInt64 = 0
        var totalMemorySize = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &totalMemoryBytes, &totalMemorySize, nil, 0) == 0 else {
            return nil
        }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return nil
        }

        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let usedBytes = min(totalMemoryBytes, usedPages * UInt64(pageSize))

        return MemorySample(usedBytes: usedBytes, totalBytes: totalMemoryBytes)
    }

    private static func loadNetworkCounters(at timestamp: Date) -> NetworkCounters? {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return nil
        }
        defer { freeifaddrs(interfaceAddresses) }

        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        var currentAddress: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let address = currentAddress {
            let interface = address.pointee
            let flags = Int32(interface.ifa_flags)
            let interfaceName = String(cString: interface.ifa_name)

            if shouldIncludeNetworkInterface(named: interfaceName, flags: flags),
               let socketAddress = interface.ifa_addr,
               socketAddress.pointee.sa_family == UInt8(AF_LINK),
               let interfaceData = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                receivedBytes += UInt64(interfaceData.pointee.ifi_ibytes)
                sentBytes += UInt64(interfaceData.pointee.ifi_obytes)
            }

            currentAddress = interface.ifa_next
        }

        return NetworkCounters(
            timestamp: timestamp,
            receivedBytes: receivedBytes,
            sentBytes: sentBytes
        )
    }

    private static func networkThroughput(
        from previous: NetworkCounters,
        to current: NetworkCounters
    ) -> NetworkThroughput {
        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else {
            return .zero
        }

        let receivedDelta = current.receivedBytes >= previous.receivedBytes
            ? current.receivedBytes - previous.receivedBytes
            : 0
        let sentDelta = current.sentBytes >= previous.sentBytes
            ? current.sentBytes - previous.sentBytes
            : 0

        return NetworkThroughput(
            receivedBytesPerSecond: Double(receivedDelta) / elapsed,
            sentBytesPerSecond: Double(sentDelta) / elapsed
        )
    }

    private static func shouldIncludeNetworkInterface(named interfaceName: String, flags: Int32) -> Bool {
        guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else {
            return false
        }

        let excludedPrefixes = ["awdl", "llw", "utun", "bridge", "anpi"]
        return !excludedPrefixes.contains(where: interfaceName.hasPrefix)
    }
}

struct SystemStatusSnapshot: Equatable {
    let cpuUsagePercent: Double
    let memoryUsagePercent: Double
    let usedMemoryBytes: UInt64
    let totalMemoryBytes: UInt64
    let receivedBytesPerSecond: Double
    let sentBytesPerSecond: Double

    var totalNetworkBytesPerSecond: Double {
        receivedBytesPerSecond + sentBytesPerSecond
    }

    var metrics: [SystemStatusMetricSnapshot] {
        [
            SystemStatusMetricSnapshot(
                kind: .cpu,
                primaryText: Self.percentText(cpuUsagePercent),
                secondaryText: "CPU",
                progress: min(1, max(0, cpuUsagePercent / 100))
            ),
            SystemStatusMetricSnapshot(
                kind: .memory,
                primaryText: Self.percentText(memoryUsagePercent),
                secondaryText: "MEM",
                progress: min(1, max(0, memoryUsagePercent / 100))
            ),
            SystemStatusMetricSnapshot(
                kind: .network,
                primaryText: Self.compactRateText(totalNetworkBytesPerSecond),
                secondaryText: "NET",
                progress: Self.networkProgress(totalNetworkBytesPerSecond)
            ),
        ]
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func compactRateText(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var value = max(0, bytesPerSecond)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value.rounded()))\(units[unitIndex])"
        }

        let formatted = value >= 10
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
        return "\(formatted)\(units[unitIndex])"
    }

    private static func networkProgress(_ bytesPerSecond: Double) -> Double {
        let ceiling = 25 * 1_024 * 1_024.0
        guard bytesPerSecond > 0 else {
            return 0
        }

        return min(1, log10(1 + bytesPerSecond) / log10(1 + ceiling))
    }
}

struct SystemStatusMetricSnapshot: Equatable, Identifiable {
    let kind: SystemStatusMetricKind
    let primaryText: String
    let secondaryText: String
    let progress: Double

    var id: String {
        kind.rawValue
    }
}

enum SystemStatusMetricKind: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case network

    var id: String {
        rawValue
    }

    var symbolName: String {
        switch self {
        case .cpu:
            "cpu"
        case .memory:
            "memorychip"
        case .network:
            "network"
        }
    }
}

private struct CPUSample {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

private struct MemorySample {
    let usedBytes: UInt64
    let totalBytes: UInt64

    var usagePercent: Double {
        guard totalBytes > 0 else {
            return 0
        }

        return min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100))
    }
}

private struct NetworkCounters {
    let timestamp: Date
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

private struct NetworkThroughput {
    let receivedBytesPerSecond: Double
    let sentBytesPerSecond: Double

    static let zero = NetworkThroughput(receivedBytesPerSecond: 0, sentBytesPerSecond: 0)
}
