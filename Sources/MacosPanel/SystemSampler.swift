import Darwin
import Foundation

// MARK: - Snapshot models

struct Snapshot {
    var cpu: CPUSnapshot?
    var memory: MemorySnapshot?
    var volumes: [VolumeSnapshot]
    var date: Date

    static let empty = Snapshot(cpu: nil, memory: nil, volumes: [], date: .distantPast)
}

struct CPUSnapshot {
    struct LoadAverage {
        let one: Double
        let five: Double
        let fifteen: Double
    }

    /// Overall busy fraction (user + nice + system), 0...1.
    let usage: Double
    /// Share of CPU time spent in user code, including nice, 0...1.
    let user: Double
    /// Share of CPU time spent in the kernel, 0...1.
    let system: Double
    let coreCount: Int
    let loadAverage: LoadAverage?
}

struct MemorySnapshot {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let free: UInt64
    let swapTotal: UInt64
    let swapUsed: UInt64

    /// Memory reported as "used" in Activity Monitor: App + Wired + Compressed.
    var used: UInt64 { app &+ wired &+ compressed }

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }
}

struct VolumeSnapshot: Identifiable {
    let id: String
    let name: String
    let total: UInt64
    let free: UInt64
    let isPrimary: Bool

    var used: UInt64 { total > free ? total - free : 0 }

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }
}

// MARK: - Sampler

enum SystemSampler {
    static func snapshot() -> Snapshot {
        Snapshot(cpu: cpu(), memory: memory(), volumes: volumes(), date: Date())
    }

    // MARK: CPU

    private struct CPUTicks {
        var user: UInt32 = 0
        var system: UInt32 = 0
        var idle: UInt32 = 0
        var nice: UInt32 = 0
    }

    private static let cpuLock = NSLock()
    private static var previousCPUTicks: [CPUTicks] = []

    /// Percentages are computed from the tick deltas since the previous sample. The first
    /// sample has no predecessor, so it reports the average since boot.
    static func cpu() -> CPUSnapshot? {
        guard let current = cpuTicks(), !current.isEmpty else { return nil }

        cpuLock.lock()
        let previous = previousCPUTicks
        previousCPUTicks = current
        cpuLock.unlock()

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        for (index, ticks) in current.enumerated() {
            let old = index < previous.count ? previous[index] : CPUTicks()
            // Tick counters are 32-bit and wrap on long uptimes.
            user &+= UInt64(ticks.user &- old.user)
            system &+= UInt64(ticks.system &- old.system)
            idle &+= UInt64(ticks.idle &- old.idle)
            nice &+= UInt64(ticks.nice &- old.nice)
        }

        let busy = user &+ nice &+ system
        let total = busy &+ idle
        guard total > 0 else { return nil }

        return CPUSnapshot(
            usage: Double(busy) / Double(total),
            user: Double(user &+ nice) / Double(total),
            system: Double(system) / Double(total),
            coreCount: current.count,
            loadAverage: loadAverages()
        )
    }

    private static func cpuTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }

        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        return info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) { loads in
            (0..<Int(cpuCount)).map { index in
                CPUTicks(
                    user: loads[index].cpu_ticks.0,
                    system: loads[index].cpu_ticks.1,
                    idle: loads[index].cpu_ticks.2,
                    nice: loads[index].cpu_ticks.3
                )
            }
        }
    }

    private static func loadAverages() -> CPUSnapshot.LoadAverage? {
        var values = [Double](repeating: 0, count: 3)
        let count = values.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, 3)
        }
        guard count == 3 else { return nil }
        return CPUSnapshot.LoadAverage(one: values[0], five: values[1], fifteen: values[2])
    }

    // MARK: Memory

    static func memory() -> MemorySnapshot? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let page = UInt64(pageSize)

        let purgeable = UInt64(stats.purgeable_count) &* page
        let app = UInt64(stats.internal_page_count) &* page > purgeable
            ? UInt64(stats.internal_page_count) &* page &- purgeable
            : 0
        let wired = UInt64(stats.wire_count) &* page
        let compressed = UInt64(stats.compressor_page_count) &* page
        let cached = UInt64(stats.external_page_count) &* page &+ purgeable

        let total = ProcessInfo.processInfo.physicalMemory
        let used = app &+ wired &+ compressed
        let free = total > used + cached ? total &- used &- cached : 0
        let swap = swapUsage()

        return MemorySnapshot(
            total: total,
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            free: free,
            swapTotal: swap.total,
            swapUsed: swap.used
        )
    }

    private static func swapUsage() -> (total: UInt64, used: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (UInt64(usage.xsu_total), UInt64(usage.xsu_used))
    }

    // MARK: Storage

    static func volumes() -> [VolumeSnapshot] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsLocalKey,
            .volumeIsBrowsableKey,
            .volumeIsReadOnlyKey,
            .volumeIsInternalKey,
        ]

        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        var result: [VolumeSnapshot] = []

        for url in urls {
            // The APFS data volume mirrors the boot volume; don't show it twice.
            guard !url.path.hasPrefix("/System/Volumes/") else { continue }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            guard values.volumeIsLocal == true, values.volumeIsBrowsable == true else { continue }
            guard values.volumeIsReadOnly != true else { continue }

            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            guard total > 0 else { continue }

            let important = values.volumeAvailableCapacityForImportantUsage ?? 0
            let plain = Int64(values.volumeAvailableCapacity ?? 0)
            let rawFree = important > 0 ? important : plain
            let free = UInt64(max(0, min(rawFree, Int64(clamping: total))))

            result.append(
                VolumeSnapshot(
                    id: url.path,
                    name: values.volumeName ?? url.lastPathComponent,
                    total: total,
                    free: free,
                    isPrimary: url.path == "/"
                )
            )
        }

        // Fall back to plain filesystem attributes if the boot volume is missing.
        if !result.contains(where: { $0.isPrimary }),
           let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            let total = UInt64((attributes[.systemSize] as? NSNumber)?.int64Value ?? 0)
            let free = UInt64((attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
            result.insert(
                VolumeSnapshot(
                    id: "/",
                    name: "Macintosh HD",
                    total: total,
                    free: min(free, total),
                    isPrimary: true
                ),
                at: 0
            )
        }

        return result.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
