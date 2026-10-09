import Foundation
import Testing
@testable import MacpeekCore

@Suite struct FormatTests {
    @Test func bytes() {
        #expect(Format.bytes(512) == "512 B")
        #expect(Format.bytes(366_400_000_000) == "366.4 GB")
        #expect(Format.memory(8 * 1024 * 1024 * 1024) == "8.0 GB")
        #expect(Format.rate(1_200_000) == "1.2 MB/s")
        #expect(Format.rate(-5) == "0 B/s")
        #expect(Format.rate(999_940) == "999.9 KB/s")
        #expect(Format.rate(999_960) == "1.0 MB/s")
        #expect(Format.bytes(999_990_000_000) == "1.0 TB")
    }

    @Test func percent() {
        #expect(Format.percent(0.424) == "42%")
        #expect(Format.percent(1) == "100%")
    }

    @Test func ago() {
        let now = Date(timeIntervalSince1970: 100_000)
        #expect(Format.ago(now.addingTimeInterval(-10), now: now) == "just now")
        #expect(Format.ago(now.addingTimeInterval(-180), now: now) == "3 min ago")
        #expect(Format.ago(now.addingTimeInterval(-7200), now: now) == "2 h ago")
    }

    @Test func duration() {
        #expect(Format.duration(minutes: 125) == "2:05")
        #expect(Format.duration(minutes: 59) == "0:59")
    }

    @Test func flags() {
        #expect(Format.flag("JP") == "🇯🇵")
        #expect(Format.flag("kh") == "🇰🇭")
        #expect(Format.flag("Japan") == nil)
    }

    @Test func historyKeepsNewest() {
        var history = History<Int>(capacity: 3)
        for value in 1...5 { history.append(value) }
        #expect(history.values == [3, 4, 5])
        #expect(history.last == 5)
    }

    @Test func thermalThrottling() {
        #expect(Thermal.level(.serious).isThrottling)
        #expect(!Thermal.level(.fair).isThrottling)
    }
}

@Suite struct KeyComboTests {
    @Test func defaultShortcut() {
        #expect(KeyCombo.default.display == "⌃⌥⌘M")
        #expect(KeyCombo.default.carbonModifiers == 0x1900)
        #expect(KeyCombo.default.isValid)
    }

    @Test func needsAModifier() {
        #expect(!KeyCombo(keyCode: 46, key: "m", command: false, option: false, control: false, shift: true).isValid)
        #expect(!KeyCombo(keyCode: 0, key: "", command: true, option: false, control: false, shift: false).isValid)
    }

    @Test func survivesStorage() throws {
        let data = try JSONEncoder().encode(KeyCombo.default)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == .default)
    }
}
