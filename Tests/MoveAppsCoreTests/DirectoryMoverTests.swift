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

        #expect(outcome == .copiedPendingDeletion(missingPaths: []))
    }

    /// The BmadBrowser incident: a source tree containing a stale `.git/fsmonitor--daemon.ipc`
    /// UNIX socket (left behind whenever `core.fsmonitor` has ever run) made real `ditto` exit
    /// non-zero even though it copied every other file — the old exit-code gate turned a fully
    /// successful transfer into a hard failure, and the pipeline never cleaned up the resulting
    /// destination directory, so every retry then also failed on "destination already exists".
    /// Exercises the *real* `DittoCopier` (not the fault-injecting fake) so the fix is proven
    /// against actual `ditto` behavior, not an assumption about it.
    @Test("copy tolerates a source containing a UNIX socket ditto cannot duplicate")
    func toleratesUncopyableSocketFile() async {
        let tmp = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("project")
        Fixture.write("a\n", to: source.appendingPathComponent("a.txt"))
        Fixture.write("b\n", to: source.appendingPathComponent("sub/b.txt"))
        Fixture.makeUnixSocket(at: source.appendingPathComponent(".git/fsmonitor--daemon.ipc"))

        let destination = tmp.appendingPathComponent("copy")
        let mover = DirectoryMover(copier: DittoCopier(), alwaysUseCopier: true)
        let outcome = await mover.move(from: source, to: destination)

        #expect(outcome == .copiedPendingDeletion(missingPaths: []))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("a.txt").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("sub/b.txt").path))
        // The source is still present — deletion is the pipeline's call, not the mover's.
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("a.txt").path))
    }

    /// A real, substantive copy failure (not just an uncopyable special file) must leave no
    /// partial destination behind — otherwise a retry immediately trips "destination already
    /// exists" with no way to recover, which is exactly how the BmadBrowser transfer got stuck.
    @Test("failed copy cleans up the partial destination it created")
    func cleansUpPartialDestinationOnFailure() async {
        let tmp = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("project")
        Fixture.write("a\n", to: source.appendingPathComponent("a.txt"))
        Fixture.write("b\n", to: source.appendingPathComponent("sub/b.txt"))

        let destination = tmp.appendingPathComponent("copy")
        let mover = DirectoryMover(
            copier: FaultInjectingCopier(drop: "sub/b.txt", compensateCount: false),
            alwaysUseCopier: true
        )
        let outcome = await mover.move(from: source, to: destination)

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
