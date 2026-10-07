import AppKit
import MacpeekCore

/// Draws the whole menu bar item as one image: CPU history, RAM fill, optional text columns
/// and the VPN shield. By default it's a template image, so macOS tints it like its own items
/// (light, dark, tinted, clicked). Colour is used only for a warning, or when the user opts in.
enum MenuBarGraph {
    static let historyLength = 28

    struct Column: Equatable {
        var top: String
        var bottom: String
    }

    struct State: Equatable {
        /// Percent, oldest first.
        var cpu: [Int]
        var ram: Int
        var pressure: MemoryPressure
        var network: Column?
        var disk: Column?
        /// Nil hides the shield.
        var vpn: Bool?
        var colored = false

        /// A critical warning needs real red, which a template image can't carry.
        var isTemplate: Bool { !colored && pressure != .critical }
    }

    private static let height: CGFloat = 18
    private static let symbolWidth: CGFloat = 14
    private static let cpuWidth: CGFloat = 28
    private static let ramWidth: CGFloat = 20
    private static let boxHeight: CGFloat = 13
    private static let gap: CGFloat = 6
    /// Apple's opacity for inactive menu bar states.
    private static let dimmed: CGFloat = 0.35

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
        var width = symbolWidth + 2 + cpuWidth + gap + symbolWidth + 2 + ramWidth
        for column in [state.network, state.disk].compactMap({ $0 }) {
            width += gap + columnWidth(column)
        }
        if state.vpn != nil { width += gap + 15 }
        return ceil(width)
    }

    @MainActor
    private static func draw(_ state: State, in rect: NSRect) {
        let palette = Palette(state)
        let boxY = (height - boxHeight) / 2
        var x: CGFloat = 0

        drawSymbol("cpu", color: palette.ink, in: NSRect(x: x, y: boxY, width: symbolWidth, height: boxHeight))
        x += symbolWidth + 2
        let cpuBox = NSRect(x: x, y: boxY, width: cpuWidth, height: boxHeight)
        drawFrame(cpuBox, color: palette.frame)
        drawHistory(state.cpu, in: cpuBox.insetBy(dx: 1.5, dy: 1.5), color: palette.cpu)
        x = cpuBox.maxX + gap

        drawSymbol("memorychip", color: palette.ink, in: NSRect(x: x, y: boxY, width: symbolWidth, height: boxHeight))
        x += symbolWidth + 2
        let ramBox = NSRect(x: x, y: boxY, width: ramWidth, height: boxHeight)
        drawFrame(ramBox, color: palette.frame)
        let inner = ramBox.insetBy(dx: 1.5, dy: 1.5)
        var fill = inner
        fill.size.height = inner.height * CGFloat(min(100, max(0, state.ram))) / 100
        palette.ram.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
        x = ramBox.maxX

        if let network = state.network {
            x = drawColumn(network, at: x + gap, colors: (palette.ink, palette.ink))
        }
        if let disk = state.disk {
            x = drawColumn(disk, at: x + gap, colors: state.colored ? (.systemOrange, .systemBlue) : (palette.ink, palette.ink))
        }
        if let vpn = state.vpn {
            let color: NSColor = vpn ? (state.colored ? .systemGreen : palette.ink) : palette.ink.withAlphaComponent(dimmed)
            drawSymbol(vpn ? "lock.shield.fill" : "shield.slash", color: color,
                       in: NSRect(x: x + gap, y: boxY, width: 15, height: boxHeight))
        }
    }

    /// Template images only use alpha, so they're drawn in black and macOS supplies the colour.
    @MainActor
    private struct Palette {
        let ink: NSColor
        let frame: NSColor
        let cpu: NSColor
        let ram: NSColor

        init(_ state: State) {
            ink = state.isTemplate ? .black : .labelColor
            frame = ink.withAlphaComponent(0.4)
            cpu = state.colored ? .systemBlue : ink
            switch (state.pressure, state.colored) {
            case (.critical, _): ram = .systemRed
            case (.warning, true): ram = .systemYellow
            case (_, true): ram = .systemGreen
            default: ram = ink
            }
        }
    }

    @MainActor
    private static func drawSymbol(_ name: String, color: NSColor, in box: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = symbol.size
        symbol.draw(in: NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                               width: size.width, height: size.height))
    }

    @MainActor
    private static func drawFrame(_ box: NSRect, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        path.lineWidth = 1
        path.stroke()
    }

    /// Filled area, newest sample at the right edge.
    @MainActor
    private static func drawHistory(_ values: [Int], in box: NSRect, color: NSColor) {
        guard values.count > 1 else { return }
        let step = box.width / CGFloat(historyLength - 1)
        let start = box.maxX - step * CGFloat(values.count - 1)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: start, y: box.minY))
        for (index, value) in values.enumerated() {
            let y = box.minY + box.height * CGFloat(min(100, max(0, value))) / 100
            path.line(to: NSPoint(x: start + step * CGFloat(index), y: y))
        }
        path.line(to: NSPoint(x: box.maxX, y: box.minY))
        path.close()
        color.setFill()
        path.fill()
    }

    @MainActor
    private static let columnFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    @MainActor
    private static func columnWidth(_ column: Column) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: columnFont]
        return max(NSString(string: column.top).size(withAttributes: attributes).width,
                   NSString(string: column.bottom).size(withAttributes: attributes).width)
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
