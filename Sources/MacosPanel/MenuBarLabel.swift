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

    var body: some View {
        Image(nsImage: MenuBarIcon.make(display: display, memory: monitor.snapshot.memory, volume: primaryVolume))
            .renderingMode(.original)
            .help(helpText)
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
