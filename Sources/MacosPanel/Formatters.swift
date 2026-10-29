import Foundation

enum ByteFormat {
    private static let ram: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.isAdaptive = true
        formatter.includesUnit = true
        return formatter
    }()

    private static let disk: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.isAdaptive = true
        formatter.includesUnit = true
        return formatter
    }()

    static func ram(_ bytes: UInt64) -> String {
        ram.string(fromByteCount: Int64(clamping: bytes))
    }

    static func disk(_ bytes: UInt64) -> String {
        disk.string(fromByteCount: Int64(clamping: bytes))
    }

    /// Very short, fixed-ish width label for the menu bar, e.g. "214G" or "12.4G".
    static func compactFree(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1000 {
            return String(format: "%.1fT", gigabytes / 1000)
        }
        if gigabytes >= 10 {
            return String(format: "%.0fG", gigabytes)
        }
        return String(format: "%.1fG", gigabytes)
    }
}

extension Double {
    var percentText: String {
        "\(Int((self * 100).rounded()))%"
    }
}
