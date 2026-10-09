import AppKit
import MacpeekCore

/// Draws the whole menu bar item as one image: a CPU ring, a memory level and optional text columns.
/// By default it's a template image, so macOS tints it like its own items
/// (light, dark, tinted, clicked). Colour is used only for a warning, or when the user opts in.
enum MenuBarGraph {
    struct Column: Equatable {
        var top: String
        var bottom: String
        /// Room for the widest value, so the item keeps one width as the numbers change.
        var reserved: CGFloat = 0
    }

    struct State: Equatable {
        /// Percent.
        var cpu: Int
        /// Memory pressure, percent.
        var ram: Int
        var pressure: MemoryPressure
        var network: Column?
        var disk: Column?
        var colored = false

        /// A pressure warning needs real colour, which a template image can't carry.
        var isTemplate: Bool { !colored && pressure == .normal }
    }

    private static let height: CGFloat = 18
    /// Bjango's size for round menu bar items, which matches the weight of the system icons.
    private static let ringSize: CGFloat = 16
    private static let ringWidth: CGFloat = 2.5
    private static let pillSize = NSSize(width: 7, height: 14)
    private static let gap: CGFloat = 5

    @MainActor
    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: width(state), height: height), flipped: false) { rect in
            MainActor.assumeIsolated { draw(state, in: rect) }
            return true
        }
        image.isTemplate = state.isTemplate
        return image
    }

    @MainActor
    private static func width(_ state: State) -> CGFloat {
        var width = ringSize + gap + pillSize.width
        for column in [state.network, state.disk].compactMap({ $0 }) {
            width += gap + 1 + columnWidth(column)
        }
        return ceil(width)
    }

    @MainActor
    private static func draw(_ state: State, in rect: NSRect) {
        let palette = Palette(state)
        drawRing(CGFloat(min(100, max(0, state.cpu))) / 100, color: palette.cpu, track: palette.faint)
        var x = drawPill(fill: CGFloat(min(100, max(0, state.ram))) / 100, at: ringSize + gap,
                         color: palette.ram, outline: palette.outline)
        if let network = state.network {
            x = drawColumn(network, at: x + gap + 1, colors: (palette.ink, palette.ink))
        }
        if let disk = state.disk {
            x = drawColumn(disk, at: x + gap + 1, colors: state.colored ? (.systemOrange, .systemBlue) : (palette.ink, palette.ink))
        }
    }

    /// Template images only use alpha, so they're drawn in black and macOS supplies the colour.
    @MainActor
    private struct Palette {
        let ink: NSColor
        let faint: NSColor
        let outline: NSColor
        let cpu: NSColor
        let ram: NSColor

        init(_ state: State) {
            ink = state.isTemplate ? .black : .labelColor
            faint = ink.withAlphaComponent(0.25)
            outline = ink.withAlphaComponent(0.45)
            cpu = state.colored ? .systemBlue : ink
            switch (state.pressure, state.colored) {
            case (.critical, _): ram = .systemRed
            case (.warning, _): ram = .systemYellow
            case (_, true): ram = .systemGreen
            default: ram = ink
            }
        }
    }

    /// A faint full track with the load as a solid arc clockwise from the top. A sliver always
    /// shows, so an idle Mac doesn't look like an empty ring.
    @MainActor
    private static func drawRing(_ load: CGFloat, color: NSColor, track: NSColor) {
        let center = NSPoint(x: ringSize / 2, y: height / 2)
        let radius = (ringSize - ringWidth) / 2
        let circle = NSBezierPath()
        circle.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        circle.lineWidth = ringWidth
        track.setStroke()
        circle.stroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * max(0.03, min(1, load)),
                      clockwise: true)
        arc.lineWidth = ringWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    /// Memory as a level, drawn like the battery glyph: a faint outline filled from the bottom.
    @MainActor
    private static func drawPill(fill: CGFloat, at x: CGFloat, color: NSColor, outline: NSColor) -> CGFloat {
        let box = NSRect(x: x, y: (height - pillSize.height) / 2, width: pillSize.width, height: pillSize.height)
        outline.setStroke()
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
        path.lineWidth = 1
        path.stroke()
        let inner = box.insetBy(dx: 1.75, dy: 1.75)
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: max(1, inner.height * fill)),
                     xRadius: 1.25, yRadius: 1.25).fill()
        return box.maxX
    }

    @MainActor
    private static let columnFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    @MainActor
    static let rateWidth = widest(["↓ ", "↑ "], units: ["B/s", "KB/s", "MB/s", "GB/s"])
    @MainActor
    static let sizeWidth = widest(["F: ", "U: "], units: ["B", "KB", "MB", "GB", "TB"])

    /// Digits are monospaced, so "999.9" is as wide as any number `Format` shows.
    @MainActor
    private static func widest(_ prefixes: [String], units: [String]) -> CGFloat {
        prefixes.flatMap { prefix in units.map { textWidth(prefix + "999.9 " + $0) } }.max() ?? 0
    }

    @MainActor
    private static func textWidth(_ text: String) -> CGFloat {
        ceil(NSString(string: text).size(withAttributes: [.font: columnFont]).width)
    }

    @MainActor
    private static func columnWidth(_ column: Column) -> CGFloat {
        max(column.reserved, textWidth(column.top), textWidth(column.bottom))
    }

    @MainActor
    private static func drawColumn(_ column: Column, at x: CGFloat, colors: (NSColor, NSColor)) -> CGFloat {
        NSString(string: column.top).draw(at: NSPoint(x: x, y: 8.5),
                                          withAttributes: [.font: columnFont, .foregroundColor: colors.0])
        NSString(string: column.bottom).draw(at: NSPoint(x: x, y: -1),
                                             withAttributes: [.font: columnFont, .foregroundColor: colors.1])
        return x + columnWidth(column)
    }
}
