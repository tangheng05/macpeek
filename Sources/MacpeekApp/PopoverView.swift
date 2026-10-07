import AppKit
import MacpeekCore
import SwiftUI

struct PopoverView: View {
    let model: AppModel
    /// False while closed, so nothing inside keeps re-rendering in the background.
    let visible: Bool

    var body: some View {
        if visible {
            VStack(alignment: .leading, spacing: 12) {
                PrivacySection(model: model)
                Divider()
                SystemSection(model: model)
                Divider()
                NetworkSection(model: model)
                Divider()
                PowerSection(model: model)
                Divider()
                footer
            }
            .padding(16)
            .frame(width: 320)
        } else {
            Color.clear.frame(width: 320, height: 1)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let release = model.updater.available {
                Button("Update to \(release.version)") { Task { await model.updater.install() } }
                    .disabled(model.updater.status == .installing)
            }
            HStack {
                Button("Settings…") { model.openSettings?() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit Macpeek") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// A slim coloured bar; ProgressView ignores tint on macOS.
struct Meter: View {
    let value: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color.gradient)
                    .frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 6)
    }
}

/// Filled area of 0...1 values, newest on the right.
struct Sparkline: Shape {
    let values: [Double]
    let capacity: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(max(1, capacity - 1))
        let start = rect.maxX - step * CGFloat(values.count - 1)
        path.move(to: CGPoint(x: start, y: rect.maxY))
        for (index, value) in values.enumerated() {
            path.addLine(to: CGPoint(x: start + step * CGFloat(index), y: rect.maxY - rect.height * min(1, max(0, value))))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// App icons, looked up once per app.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for path: String?) -> NSImage {
        guard let path else { return NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage() }
        if let icon = cache[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}
