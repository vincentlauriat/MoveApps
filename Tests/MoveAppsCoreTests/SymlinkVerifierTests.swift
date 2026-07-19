import Foundation
import Testing
@testable import MoveAppsCore

@Suite("SymlinkVerifier")
struct SymlinkVerifierTests {
    @Test("flags cross-project symlink but not a self-referential build symlink")
    func crossProjectVsBuild() {
        let apps = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: apps) }
        let fm = FileManager.default

        let projA = apps.appendingPathComponent("ProjA")
        let projB = apps.appendingPathComponent("ProjB")
        try? fm.createDirectory(at: projA, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projB, withIntermediateDirectories: true)
        Fixture.write("hello", to: projB.appendingPathComponent("shared.txt"))

        // Cross-project link: ProjA -> ProjB's tree (absolute).
        try? fm.createSymbolicLink(
            atPath: projA.appendingPathComponent("link-to-b").path,
            withDestinationPath: projB.path
        )

        // Self-referential, broken, inside build/ -> must be ignored (benign build artifact).
        let buildDir = projA.appendingPathComponent("build")
        try? fm.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(
            atPath: buildDir.appendingPathComponent("self").path,
            withDestinationPath: buildDir.appendingPathComponent("self").path
        )

        let warnings = SymlinkVerifier().scan(root: projA)

        // Exactly one warning, and it is the cross-project one pointing at ProjB.
        #expect(warnings.count == 1)
        let crossProject = warnings.compactMap { warning -> String? in
            if case .crossProjectSymlink(_, _, let other) = warning { return other }
            return nil
        }
        #expect(crossProject == ["ProjB"])
    }

    @Test("flags a broken internal symlink")
    func brokenInternal() {
        let apps = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: apps) }
        let proj = apps.appendingPathComponent("Proj")
        try? FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(
            atPath: proj.appendingPathComponent("dangling").path,
            withDestinationPath: proj.appendingPathComponent("missing-target.txt").path
        )

        let warnings = SymlinkVerifier().scan(root: proj)
        let broken = warnings.contains { if case .brokenSymlink = $0 { return true }; return false }
        #expect(broken)
    }

    @Test("an unreadable root is flagged as incomplete, not silently clean")
    func unreadableRootIsIncomplete() {
        // A non-existent root makes `contentsOfDirectory` throw — the same failure branch a
        // permission-denied root hits. The scan must surface `.symlinkScanIncomplete` rather than
        // return an empty (falsely clean) result.
        let missing = Fixture.makeTempDir().appendingPathComponent("does-not-exist")

        let warnings = SymlinkVerifier().scan(root: missing)
        let incomplete = warnings.contains { if case .symlinkScanIncomplete = $0 { return true }; return false }
        #expect(incomplete)
    }
}
