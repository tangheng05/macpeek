import AppKit
import MacpeekCore

/// Draws the whole menu bar item as one image: CPU history, RAM fill, optional text columns
/// and the VPN shield. Colours resolve at draw time, so light and dark menu bars both work.
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
    }

    private static let height: CGFloat = 18
    private static let cpuWidth: CGFloat = 30
    private static let ramWidth: CGFloat = 22
    private static let labelWidth: CGFloat = 6
    private static let gap: CGFloat = 5

    @MainActor
    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: width(state), height: height), flipped: false) { rect in
            MainActor.assumeIsolated { draw(state, in: rect) }
            return true
        }
        image.isTemplate = false
        return image
    }

    @MainActor
    private static func width(_ state: State) -> CGFloat {
        var width = labelWidth + cpuWidth + gap + labelWidth + ramWidth
        for column in [state.network, state.disk].compactMap({ $0 }) {
            width += gap + columnWidth(column)
        }
        if state.vpn != nil { width += gap + 14 }
        return ceil(width)
    }

    @MainActor
    private static func draw(_ state: State, in rect: NSRect) {
        var x: CGFloat = 0
        x = drawLabel("CPU", at: x)
        let cpuBox = NSRect(x: x, y: 2, width: cpuWidth, height: 14)
        drawFrame(cpuBox)
        drawHistory(state.cpu, in: cpuBox.insetBy(dx: 1.5, dy: 1.5))
        x = cpuBox.maxX + gap

        x = drawLabel("RAM", at: x)
        let ramBox = NSRect(x: x, y: 2, width: ramWidth, height: 14)
        drawFrame(ramBox)
        let inner = ramBox.insetBy(dx: 1.5, dy: 1.5)
        var fill = inner
        fill.size.height = inner.height * CGFloat(min(100, max(0, state.ram))) / 100
        color(for: state.pressure).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
        x = ramBox.maxX

        if let network = state.network {
            x = drawColumn(network, at: x + gap, colors: (.labelColor, .labelColor))
        }
        if let disk = state.disk {
            x = drawColumn(disk, at: x + gap, colors: (.systemOrange, .systemBlue))
        }
        if let vpn = state.vpn {
            drawShield(on: vpn, in: NSRect(x: x + gap, y: 2, width: 14, height: 14))
        }
    }

    /// Letters stacked vertically, like the classic CPU/RAM meters.
    @MainActor
    private static func drawLabel(_ text: String, at x: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 5.5, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ]
        for (index, letter) in text.enumerated() {
            let y = height - 3 - CGFloat(index + 1) * 5
            NSString(string: String(letter)).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }
        return x + labelWidth
    }

    @MainActor
    private static func drawFrame(_ box: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
        path.lineWidth = 1
        path.stroke()
    }

    /// Filled area, newest sample at the right edge.
    @MainActor
    private static func drawHistory(_ values: [Int], in box: NSRect) {
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
        NSColor.systemBlue.setFill()
        path.fill()
    }

    @MainActor
    private static let columnFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)

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
        NSString(string: column.bottom).draw(at: NSPoint(x: x, y: -0.5),
                                             withAttributes: [.font: columnFont, .foregroundColor: colors.1])
        return x + columnWidth(column)
    }

    @MainActor
    private static func drawShield(on: Bool, in box: NSRect) {
        let name = on ? "lock.shield.fill" : "shield.slash"
        let tint: NSColor = on ? .systemGreen : .secondaryLabelColor
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?
            .draw(in: box)
    }

    @MainActor
    private static func color(for pressure: MemoryPressure) -> NSColor {
        switch pressure {
        case .normal: .systemGreen
        case .warning: .systemYellow
        case .critical: .systemRed
        }
    }
}
