import AppKit
import MacpeekCore
import SwiftUI

struct PopoverView: View {
    let model: AppModel
    /// False while closed, so nothing inside keeps re-rendering in the background.
    let visible: Bool
    var onResize: ((CGFloat) -> Void)?

    var body: some View {
        if visible {
            VStack(alignment: .leading, spacing: 18) {
                PrivacySection(model: model)
                SystemSection(model: model)
                TopAppsSection(model: model)
                NetworkSection(model: model)
                if let power = model.power {
                    BatterySection(power: power)
                }
                footer
            }
            .padding(14)
            .frame(width: 320)
            // Report the natural height even while the popover is still at its old size.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { onResize?($0) }
        } else {
            Color.clear.frame(width: 320, height: 1)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            if let release = model.updater.available {
                if model.updater.viaHomebrew {
                    Button(model.updater.status == .copiedCommand ? "Copied" : "Copy Update Command") {
                        Task { await model.updater.install() }
                    }
                    .help("Copies \(Updater.brewCommand) to paste in Terminal")
                } else {
                    Button("Update to \(release.version)") { Task { await model.updater.install() } }
                        .disabled(model.updater.status == .installing)
                }
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

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

struct ValueRow: View {
    let label: String
    let value: String
    var valueColor: Color = .secondary

    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// One app in a ranked list; the top apps and network lists share it so they line up.
struct AppRow: View {
    static let height: CGFloat = 18
    let icon: NSImage
    let name: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(name).lineLimit(1)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: Self.height)
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
    private static var apps: [String: (name: String, path: String?)] = [:]
    private static let fallback = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage()

    static func icon(for path: String?) -> NSImage {
        guard let path else { return fallback }
        if let icon = cache[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }

    /// nettop cuts process names to 15 characters ("Brave Browser H"), so match the longest
    /// running app whose name starts the process name, then an installed app of that name.
    static func app(forProcess name: String) -> (name: String, path: String?) {
        if let app = apps[name] { return app }
        let app = lookUp(name)
        apps[name] = app
        return app
    }

    /// Apps launch and quit between popover openings, so matches only last one session.
    static func forgetApps() {
        apps.removeAll()
    }

    private static func lookUp(_ name: String) -> (name: String, path: String?) {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.localizedName.map { (name: $0, path: app.bundleURL?.path) } }
            .filter { name.hasPrefix($0.name) }
            .max { $0.name.count < $1.name.count }
        if let running { return running }
        let installed = ["/Applications", "/System/Applications"].map { "\($0)/\(name).app" }
            .first { FileManager.default.fileExists(atPath: $0) }
        return (name, installed)
    }
}
