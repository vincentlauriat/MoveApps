import Foundation
import Testing
@testable import MoveAppsCore

@Suite("DirectoryMover")
struct DirectoryMoverTests {
    /// The regression the item-count check missed: the copier drops a real file yet keeps the
    /// total item count equal by adding a stray `.DS_Store`. Counting alone saw equal totals and
    /// deleted the source; the path-set comparison must catch the missing file as `.failed`.
    @Test("copy that drops a file but keeps item counts equal is caught as failed")
    func detectsCompensatedFileLoss() async {
        let tmp = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("project")
        Fixture.write("a\n", to: source.appendingPathComponent("a.txt"))
        Fixture.write("b\n", to: source.appendingPathComponent("sub/b.txt"))

        // Drops `sub/b.txt` and adds a `.DS_Store`, so `recursiveItemCount` would have matched.
        let mover = DirectoryMover(
            copier: FaultInjectingCopier(drop: "sub/b.txt", compensateCount: true),
            alwaysUseCopier: true
        )
        let outcome = await mover.move(from: source, to: tmp.appendingPathComponent("copy"))

        guard case .failed(let reason) = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        #expect(reason.contains("sub/b.txt"))
        // The source is left intact for inspection — the mover never deletes it.
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("sub/b.txt").path))
    }

    @Test("faithful copy of every path succeeds")
    func acceptsCompleteCopy() async {
        let tmp = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("project")
        Fixture.write("a\n", to: source.appendingPathComponent("a.txt"))
        Fixture.write("b\n", to: source.appendingPathComponent("sub/b.txt"))

        let mover = DirectoryMover(copier: FaultInjectingCopier(), alwaysUseCopier: true)
        let outcome = await mover.move(from: source, to: tmp.appendingPathComponent("copy"))

        #expect(outcome == .copiedPendingDeletion)
    }
}
