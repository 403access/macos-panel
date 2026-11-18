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
    @AppStorage("menuBarShowsDeviceIcons") private var showsDeviceIcons = true
    @AppStorage("menuBarDeviceIDs") private var selectedDevices = DeviceSelection()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = snapshot {
                Image(nsImage: image)
                    .renderingMode(.original)
            } else {
                Text("—")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        }
        .help(helpText)
    }

    /// MenuBarExtra only renders one element reliably from a composed label, so the whole
    /// item is drawn into a single image. ImageRenderer keeps text and SF Symbols crisp at
    /// the display's real scale.
    private var snapshot: NSImage? {
        let content = labelContent
            .frame(height: 16)
            .fixedSize(horizontal: true, vertical: false)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(1, NSScreen.main?.backingScaleFactor ?? 2)
        return renderer.nsImage
    }

    @ViewBuilder
    private var labelContent: some View {
        if showsBars {
            HStack(spacing: 9) {
                if display.contains(.cpu), let cpu = monitor.snapshot.cpu {
                    MenuBarMetricSegment(
                        fraction: cpu.usage,
                        text: cpu.usage.percentText,
                        tint: usageTint(cpu.usage)
                    )
                }

                if display.contains(.memory), let memory = monitor.snapshot.memory {
                    MenuBarMetricSegment(
                        fraction: memory.usedFraction,
                        text: memory.usedFraction.percentText,
                        tint: usageTint(memory.usedFraction)
                    )
                }

                if display.contains(.storage), let volume = primaryVolume {
                    MenuBarMetricSegment(
                        fraction: volume.usedFraction,
                        text: ByteFormat.compactFree(volume.free),
                        tint: usageTint(volume.usedFraction)
                    )
                }

                ForEach(shownDevices) { device in
                    MenuBarDeviceSegment(device: device, showsIcon: showsDeviceIcons)
                }

                if !hasMetrics, shownDevices.isEmpty {
                    emptyLabel
                }
            }
        } else {
            HStack(spacing: 6) {
                if !textLabel.isEmpty {
                    Text(textLabel)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }

                if textLabel.isEmpty, shownDevices.isEmpty {
                    Text("—")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }

                ForEach(shownDevices) { device in
                    MenuBarDeviceTextSegment(device: device, showsIcon: showsDeviceIcons)
                }
            }
        }
    }

    private var emptyLabel: some View {
        Text("—")
            .font(.system(size: 12, weight: .medium, design: .rounded))
    }

    private var shownDevices: [DeviceBattery] {
        monitor.devices.filter { selectedDevices.contains($0.id) }
    }

    private var hasMetrics: Bool {
        (display.contains(.cpu) && monitor.snapshot.cpu != nil)
            || (display.contains(.memory) && monitor.snapshot.memory != nil)
            || (display.contains(.storage) && primaryVolume != nil)
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
        return parts.joined(separator: " · ")
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

    private func usageTint(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.70: .green
        case ..<0.88: .orange
        default: .red
        }
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
        for device in shownDevices {
            parts.append("\(device.name) \(device.statusText)")
        }
        return parts.joined(separator: " · ")
    }
}

/// One CPU / RAM / disk metric in the bar-style menu bar label.
private struct MenuBarMetricSegment: View {
    let fraction: Double
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3.5) {
            MenuBarBar(fraction: fraction, tint: tint, width: 28)

            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// One accessory in the bar-style menu bar label.
private struct MenuBarDeviceSegment: View {
    let device: DeviceBattery
    let showsIcon: Bool

    private var tint: Color { deviceTint(device) }

    var body: some View {
        HStack(spacing: 2.5) {
            if showsIcon {
                Image(systemName: device.kind.symbolName)
                    .font(.system(size: 11, weight: .medium))
            }

            MenuBarBar(fraction: device.fraction ?? 0, tint: tint, width: 20)

            Text(device.percentText)
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .fixedSize()

            if device.isCharging == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Compact device entry for text mode.
private struct MenuBarDeviceTextSegment: View {
    let device: DeviceBattery
    let showsIcon: Bool

    var body: some View {
        HStack(spacing: 2) {
            if showsIcon {
                Image(systemName: device.kind.symbolName)
            }
            Text(device.percentText)
            if device.isCharging == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(deviceTint(device))
        .fixedSize()
    }
}

private func deviceTint(_ device: DeviceBattery) -> Color {
    if device.isCharging == true { return .green }
    guard let fraction = device.fraction else { return .secondary }
    switch fraction {
    case ..<0.20: return .red
    case ..<0.50: return .orange
    default: return .green
    }
}

private struct MenuBarBar: View {
    let fraction: Double
    let tint: Color
    let width: CGFloat

    private let height: CGFloat = 6.5

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: width, height: height)

            if fraction > 0 {
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, width * min(1, fraction)), height: height)
            }
        }
        .frame(width: width, height: height)
    }
}