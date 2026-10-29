import SwiftUI

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case both
    case memory
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both: "RAM % + Disk free"
        case .memory: "RAM % only"
        case .storage: "Disk free only"
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("menuBarDisplay") private var display: MenuBarDisplay = .both

    var body: some View {
        Text(labelText)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .help(helpText)
    }

    /// Use a single `Text`: on recent macOS versions MenuBarExtra clips labels
    /// that are built from multiple views.
    private var labelText: String {
        switch display {
        case .both:
            "RAM \(memoryText) · \(storageText) free"
        case .memory:
            "RAM \(memoryText)"
        case .storage:
            "\(storageText) free"
        }
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
        if let memory = monitor.snapshot.memory {
            parts.append("RAM \(memory.usedFraction.percentText) used")
        }
        if let volume = primaryVolume {
            parts.append("\(ByteFormat.disk(volume.free)) free")
        }
        return parts.joined(separator: " · ")
    }
}
