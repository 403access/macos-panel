import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var monitor: SystemMonitor

    @AppStorage("menuBarDisplay") private var display: MenuBarDisplay = .both
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginItemError: String?

    private var primaryVolume: VolumeSnapshot? {
        monitor.snapshot.volumes.first(where: \.isPrimary) ?? monitor.snapshot.volumes.first
    }

    private var otherVolumes: [VolumeSnapshot] {
        monitor.snapshot.volumes.filter { !$0.isPrimary }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let memory = monitor.snapshot.memory {
                MemorySection(memory: memory)
                    .padding(14)
            }

            if let primary = primaryVolume {
                Divider().opacity(0.5)
                StorageSection(volume: primary, otherVolumes: otherVolumes)
                    .padding(14)
            }

            Divider().opacity(0.5)

            footer

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 302)
        .onChange(of: launchAtLogin) { _, newValue in
            guard newValue != LaunchAtLogin.isEnabled else { return }
            do {
                try LaunchAtLogin.set(newValue)
                loginItemError = nil
            } catch {
                loginItemError = "Login item: \(error.localizedDescription)"
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Picker("Menu Bar", selection: $display) {
                ForEach(MenuBarDisplay.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()

            Spacer(minLength: 0)

            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")

            Menu {
                Picker("Refresh Every", selection: $monitor.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }

                Divider()

                Toggle("Launch at Login", isOn: $launchAtLogin)

                Divider()

                Button("Quit MacosPanel") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Sections

private struct MemorySection: View {
    let memory: MemorySnapshot

    private var tint: Color { usageTint(memory.usedFraction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: "Memory", symbol: "memorychip.fill", value: memory.usedFraction.percentText, tint: tint)

            UsageBar(fraction: memory.usedFraction, tint: tint)

            HStack {
                Text("\(ByteFormat.ram(memory.used)) used of \(ByteFormat.ram(memory.total))")
                Spacer(minLength: 8)
                Text("\(ByteFormat.ram(memory.free)) free")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 18, alignment: .leading),
                    GridItem(.flexible(), spacing: 18, alignment: .leading),
                ],
                alignment: .leading,
                spacing: 6
            ) {
                StatCell(label: "App", value: ByteFormat.ram(memory.app))
                StatCell(label: "Wired", value: ByteFormat.ram(memory.wired))
                StatCell(label: "Compressed", value: ByteFormat.ram(memory.compressed))
                StatCell(label: "Cached", value: ByteFormat.ram(memory.cached))
            }

            swapLine
        }
    }

    private var swapLine: some View {
        HStack(spacing: 6) {
            Text("Swap")
            Spacer(minLength: 8)
            if memory.swapTotal > 0 {
                Text("\(ByteFormat.ram(memory.swapUsed)) of \(ByteFormat.ram(memory.swapTotal))")
            } else {
                Text("Not in use")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

private struct StorageSection: View {
    let volume: VolumeSnapshot
    let otherVolumes: [VolumeSnapshot]

    private var tint: Color { usageTint(volume.usedFraction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(
                title: "Storage",
                symbol: "internaldrive.fill",
                value: volume.usedFraction.percentText,
                tint: tint
            )

            UsageBar(fraction: volume.usedFraction, tint: tint)

            HStack {
                Text("\(ByteFormat.disk(volume.used)) used of \(ByteFormat.disk(volume.total))")
                Spacer(minLength: 8)
                Text("\(ByteFormat.disk(volume.free)) free")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            if !otherVolumes.isEmpty {
                ForEach(otherVolumes) { other in
                    HStack(spacing: 8) {
                        Text(other.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(ByteFormat.disk(other.free)) free of \(ByteFormat.disk(other.total))")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Components

private struct SectionHeader: View {
    let title: String
    let symbol: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}

private struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.75), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 7)
        .animation(.easeOut(duration: 0.25), value: fraction)
    }
}

private struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.system(size: 11))
    }
}

// MARK: - Helpers

private func usageTint(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.70: .green
    case ..<0.88: .orange
    default: .red
    }
}
