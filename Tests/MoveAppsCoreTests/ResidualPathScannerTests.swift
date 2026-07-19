import Foundation
import Testing
@testable import MoveAppsCore

@Suite("ResidualPathScanner")
struct ResidualPathScannerTests {
    @Test("an unreadable root is reported as incomplete, not silently clean")
    func unreadableRootIsIncomplete() {
        // A non-existent root makes `contentsOfDirectory` throw — the same failure branch a
        // permission-denied root hits. This must surface as `incomplete`, not an empty result that
        // looks identical to a genuinely clean tree.
        let missing = Fixture.makeTempDir().appendingPathComponent("does-not-exist")

        let result = ResidualPathScanner().scan(root: missing, forPath: "/old/path")

        #expect(result.matches.isEmpty)
        #expect(result.incomplete)
    }

    @Test("a readable but clean root is complete with no matches")
    func cleanRootIsComplete() {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        Fixture.write("nothing to see here", to: root.appendingPathComponent("readme.txt"))

        let result = ResidualPathScanner().scan(root: root, forPath: "/old/path")

        #expect(result.matches.isEmpty)
        #expect(!result.incomplete)
    }
}
