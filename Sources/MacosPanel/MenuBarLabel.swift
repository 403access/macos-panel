import SwiftUI

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case both
    case memory
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both: "RAM + Disk"
        case .memory: "RAM only"
        case .storage: "Disk only"
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("menuBarDisplay") private var display: MenuBarDisplay = .both
    @AppStorage("menuBarShowsBars") private var showsBars = true

    var body: some View {
        Group {
            if showsBars {
                Image(nsImage: MenuBarIcon.make(display: display, memory: monitor.snapshot.memory, volume: primaryVolume))
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
