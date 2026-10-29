import AppKit

/// Draws the menu bar item: a small usage bar plus a value for each visible metric.
enum MenuBarIcon {
    private struct Segment {
        let fraction: Double
        let text: String
        let tint: NSColor
    }

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
    private static let barWidth: CGFloat = 28
    private static let barHeight: CGFloat = 6.5
    private static let barTextGap: CGFloat = 3.5
    private static let segmentGap: CGFloat = 9
    private static let horizontalPadding: CGFloat = 1
    private static let imageHeight: CGFloat = 16

    static func make(display: MenuBarDisplay, memory: MemorySnapshot?, volume: VolumeSnapshot?) -> NSImage {
        var segments: [Segment] = []

        if display != .storage, let memory {
            segments.append(
                Segment(
                    fraction: memory.usedFraction,
                    text: memory.usedFraction.percentText,
                    tint: tint(for: memory.usedFraction)
                )
            )
        }

        if display != .memory, let volume {
            segments.append(
                Segment(
                    fraction: volume.usedFraction,
                    text: ByteFormat.compactFree(volume.free),
                    tint: tint(for: volume.usedFraction)
                )
            )
        }

        if segments.isEmpty {
            segments.append(Segment(fraction: 0, text: "—", tint: .systemGray))
        }

        return render(segments)
    }

    private static func tint(for fraction: Double) -> NSColor {
        switch fraction {
        case ..<0.70: .systemGreen
        case ..<0.88: .systemOrange
        default: .systemRed
        }
    }

    private static func render(_ segments: [Segment]) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidths = segments.map { ($0.text as NSString).size(withAttributes: attributes).width }

        var width = horizontalPadding * 2
        for (index, _) in segments.enumerated() {
            width += barWidth + barTextGap + textWidths[index]
            if index < segments.count - 1 {
                width += segmentGap
            }
        }

        let size = NSSize(width: ceil(width), height: imageHeight)
        let image = NSImage(size: size)

        let scale: CGFloat = 2
        if let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            representation.size = size
            image.addRepresentation(representation)
        }

        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high

        let barY = (size.height - barHeight) / 2
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        var x = horizontalPadding

        for (index, segment) in segments.enumerated() {
            let trackRect = NSRect(x: x, y: barY, width: barWidth, height: barHeight)
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: trackRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

            let fraction = min(1, max(0, segment.fraction))
            if fraction > 0 {
                let fillWidth = max(barHeight, barWidth * fraction)
                let fillRect = NSRect(x: x, y: barY, width: fillWidth, height: barHeight)
                segment.tint.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
            }

            x += barWidth + barTextGap

            let textSize = (segment.text as NSString).size(withAttributes: textAttributes)
            let textY = (size.height - textSize.height) / 2 + 0.5
            (segment.text as NSString).draw(at: NSPoint(x: x, y: textY), withAttributes: textAttributes)
            x += textSize.width

            if index < segments.count - 1 {
                x += segmentGap
            }
        }

        return image
    }
}
