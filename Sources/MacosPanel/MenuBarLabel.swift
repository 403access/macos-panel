import SwiftUI

/// Which metrics to show in the menu bar. Stored as a bitmask so any combination works.
struct MenuBarDisplay: OptionSet, RawRepresentable {
    let rawValue: Int

    static let cpu = MenuBarDisplay(rawValue: 1 << 0)
    static let memory = MenuBarDisplay(rawValue: 1 << 1)
    static let storage = MenuBarDisplay(rawValue: 1 << 2)
    static let all: MenuBarDisplay = [.cpu, .memory, .storage]

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Earlier versions stored a single string choice. Convert it once so existing
    /// preferences survive the move to independent toggles.
    static func migrateLegacyPreferenceIfNeeded(in defaults: UserDefaults = .standard) {
        let key = "menuBarDisplay"
        guard let legacy = defaults.string(forKey: key) else { return }

        let migrated: MenuBarDisplay
        switch legacy {
        case "both": migrated = [.memory, .storage]
        case "memory": migrated = .memory
        case "storage": migrated = .storage
        default: return
        }

        defaults.removeObject(forKey: key)
        defaults.set(migrated.rawValue, forKey: key)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("menuBarDisplay") private var display: MenuBarDisplay = .all
    @AppStorage("menuBarShowsBars") private var showsBars = true

    var body: some View {
        Group {
            if showsBars {
                Image(
                    nsImage: MenuBarIcon.make(
                        display: display,
                        cpu: monitor.snapshot.cpu,
                        memory: monitor.snapshot.memory,
                        volume: primaryVolume
                    )
                )
                .renderingMode(.original)
            } else {
                Text(textLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .help(helpText)
    }

    private var textLabel: String {
        var parts: [String] = []
        if display.contains(.cpu) {
            parts.append("CPU \(cpuText)")
        }
        if display.contains(.memory) {
            parts.append("RAM \(memoryText)")
        }
        if display.contains(.storage) {
            parts.append("\(storageText) free")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var cpuText: String {
        guard let cpu = monitor.snapshot.cpu else { return "—" }
        return cpu.usage.percentText
    }

    private var memoryText: String {
        guard let memory = monitor.snapshot.memory else { return "—" }
        return memory.usedFraction.percentText
    }

    private var storageText: String {
        guard let volume = primaryVolume else { return "—" }
        return ByteFormat.compactFree(volume.free)
    }

    private var primaryVolume: VolumeSnapshot? {
        monitor.snapshot.volumes.first(where: \.isPrimary) ?? monitor.snapshot.volumes.first
    }

    private var helpText: String {
        var parts: [String] = []
        if display.contains(.cpu), let cpu = monitor.snapshot.cpu {
            parts.append("CPU \(cpu.usage.percentText) used")
        }
        if display.contains(.memory), let memory = monitor.snapshot.memory {
            parts.append("RAM \(memory.usedFraction.percentText) used")
        }
        if display.contains(.storage), let volume = primaryVolume {
            parts.append("\(ByteFormat.disk(volume.free)) free")
        }
        return parts.joined(separator: " · ")
    }
}
