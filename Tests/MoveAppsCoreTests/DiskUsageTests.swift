import Foundation
import Testing
@testable import MoveAppsCore

@Suite("DiskUsage")
struct DiskUsageTests {
    @Test("reports a non-zero size for a directory with content")
    func measuresContent() async {
        let dir = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Write ~64 KB so the measured size comfortably clears one allocation block.
        let payload = String(repeating: "abcd", count: 16 * 1024)
        Fixture.write(payload, to: dir.appendingPathComponent("big.txt"))

        let bytes = await DiskUsage().sizeBytes(of: dir)
        #expect((bytes ?? 0) > 0)
    }

    @Test("returns nil for a path that doesn't exist")
    func missingPath() async {
        let dir = Fixture.makeTempDir().appendingPathComponent("nope")
        #expect(await DiskUsage().sizeBytes(of: dir) == nil)
    }

    @Test("ByteFormat renders nil as an em dash and real sizes as a non-empty localized string")
    func formatting() {
        #expect(ByteFormat.string(nil) == "—")
        // Locale-agnostic: the unit is "MB"/"Mo"/… depending on locale, so only assert the
        // string is real and carries a digit rather than pinning an English unit.
        let rendered = ByteFormat.string(5 * 1024 * 1024)
        #expect(rendered != "—")
        let hasDigit = rendered.contains { $0.isNumber }
        #expect(hasDigit)
    }
}
