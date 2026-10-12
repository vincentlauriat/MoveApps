import Foundation
import Testing
@testable import MoveAppsCore

// Serialized for the same reason as `TransferPipelineTests`: each test spawns real git
// subprocesses against throwaway repos.
//
// Reproduces the VisualRami incident (2026-10-12): the repo was already damaged when it was
// moved — its pack file gone, tracked files missing — and the transfer still ended "Terminé"
// [OK], because the before/after `git status` comparison only sees what the move changes.
@Suite("Git integrity around a transfer", .serialized)
struct GitIntegrityTests {
    private func makeScenario(
        repoName: String = "visualrami",
        files: [String: String]
    ) -> (plan: TransferPlan, roots: RootLocations, source: URL, destination: URL, cleanup: URL) {
        let tmp = Fixture.makeTempDir()
        let archiveRoot = tmp.appendingPathComponent("archive")
        let activeRoot = tmp.appendingPathComponent("active")
        try? FileManager.default.createDirectory(at: activeRoot, withIntermediateDirectories: true)

        let source = archiveRoot.appendingPathComponent(repoName)
        Fixture.makeCleanRepo(at: source, files: files)

        let project = ProjectCandidate(name: repoName, path: source, stackTags: [.git])
        let plan = TransferPlan(project: project, from: .archive, to: .active)
        let roots = RootLocations(active: activeRoot, archive: archiveRoot)
        let destination = activeRoot.appendingPathComponent(repoName)
        return (plan, roots, source, destination, tmp)
    }

    /// Packs every object, then deletes the `.pack` files and leaves their `.idx` behind —
    /// exactly what iCloud left in VisualRami's `.git/objects/pack`.
    private func deletePackFiles(in repo: URL) {
        Fixture.runGit(["gc", "-q"], in: repo)
        let packDir = repo.appendingPathComponent(".git/objects/pack")
        let packs = (try? FileManager.default.contentsOfDirectory(atPath: packDir.path)) ?? []
        for name in packs where name.hasSuffix(".pack") {
            try? FileManager.default.removeItem(at: packDir.appendingPathComponent(name))
        }
    }

    @Test("a repo whose pack file vanished before the move never ends ok")
    func missingPackIsNotOK() async {
        let scenario = makeScenario(files: ["src/game.ts": "export {}\n", "README.md": "rami\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }
        deletePackFiles(in: scenario.source)

        var integrityLines: [(GitCheckPhase, GitIntegrity)] = []
        var result: TransferResult?
        for await step in await TransferPipeline(roots: scenario.roots).run(scenario.plan) {
            if case .gitIntegrityChecked(let phase, _, let integrity) = step { integrityLines.append((phase, integrity)) }
            if case .finished(let r) = step { result = r }
        }

        #expect(result != nil)
        #expect(result?.status != .ok)
        // Precisely: a critical corruption, attributed to the source, with the fsck error count.
        #expect(result?.status == .critical)
        let corruption = result?.warnings.compactMap { warning -> (Int, Bool)? in
            if case .gitRepositoryCorrupted(_, let count, _, let preExisting) = warning { return (count, preExisting) }
            return nil
        } ?? []
        #expect(corruption.count == 1)
        #expect((corruption.first?.0 ?? 0) > 0)
        #expect(corruption.first?.1 == true)
        // And the step itself says so, on both sides of the move.
        #expect(integrityLines.map(\.0) == [.beforeMove, .afterMove])
        #expect(integrityLines.allSatisfy { $0.1.isCorrupted })
    }

    @Test("a corrupted repo moved by copy keeps its source")
    func corruptedRepoCopyPreservesSource() async {
        let scenario = makeScenario(files: ["src/game.ts": "export {}\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }
        deletePackFiles(in: scenario.source)

        let mover = DirectoryMover(copier: FaultInjectingCopier(), alwaysUseCopier: true)
        let result = await TransferPipeline(roots: scenario.roots, mover: mover).finalResult(for: scenario.plan)

        #expect(result?.status == .critical)
        #expect(result?.sourceDeleted == false)
        #expect(FileManager.default.fileExists(atPath: scenario.source.appendingPathComponent(".git").path))
    }

    @Test("a healthy repo passes the integrity check and still ends ok")
    func healthyRepoStaysOK() async {
        let scenario = makeScenario(files: ["src/game.ts": "export {}\n", "README.md": "rami\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }
        Fixture.runGit(["gc", "-q"], in: scenario.source)

        let integrity = await GitService().checkIntegrity(scenario.source)
        #expect(integrity?.isHealthy == true)

        let result = await TransferPipeline(roots: scenario.roots).finalResult(for: scenario.plan)
        #expect(result?.status == .ok)
        #expect(result?.warnings.isEmpty == true)
    }

    @Test("a non-repo directory has no integrity check")
    func nonRepoHasNoIntegrity() async {
        let dir = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        Fixture.write("plain\n", to: dir.appendingPathComponent("notes.txt"))
        #expect(await GitService().checkIntegrity(dir) == nil)
    }

    @Test("a tracked file already missing before the move never ends ok")
    func preExistingMissingTrackedFileIsNotOK() async {
        let scenario = makeScenario(files: ["src/game.ts": "export {}\n", "README.md": "rami\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }
        try? FileManager.default.removeItem(at: scenario.source.appendingPathComponent("src/game.ts"))

        let result = await TransferPipeline(roots: scenario.roots).finalResult(for: scenario.plan)

        #expect(result != nil)
        #expect(result?.status != .ok)
        // A warning, not critical (an uncommitted deletion looks the same), naming the file, and
        // not blamed on the move.
        #expect(result?.status == .warning)
        let missing = result?.warnings.compactMap { warning -> [String]? in
            if case .gitTrackedFilesAlreadyMissing(_, let paths) = warning { return paths }
            return nil
        }
        #expect(missing == [["src/game.ts"]])
        let blamedOnMove = result?.warnings.contains { if case .gitDeletedFilesDetected = $0 { return true }; return false }
        #expect(blamedOnMove == false)
    }

    @Test("a tracked file still only an iCloud stub never ends ok")
    func trackedFileStillInICloudIsNotOK() async {
        let scenario = makeScenario(files: ["src/game.ts": "export {}\n", "README.md": "rami\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }
        // The real file never arrived: only its dematerialized `.game.ts.icloud` stub is there,
        // and it is not actually ubiquitous, so the download request itself fails.
        try? FileManager.default.removeItem(at: scenario.source.appendingPathComponent("src/game.ts"))
        Fixture.write("stub", to: scenario.source.appendingPathComponent("src/.game.ts.icloud"))

        let materializer = FileProviderMaterializer(maxAttempts: 1, pollInterval: .milliseconds(5))
        let pipeline = TransferPipeline(roots: scenario.roots, materializer: materializer)
        let result = await pipeline.finalResult(for: scenario.plan)

        #expect(result != nil)
        #expect(result?.status != .ok)
        // Reported as not downloaded — not as lost — and the refused download request is surfaced.
        let notDownloaded = result?.warnings.compactMap { warning -> [String]? in
            if case .gitTrackedFilesNotDownloaded(_, let paths) = warning { return paths }
            return nil
        }
        #expect(notDownloaded == [["src/game.ts"]])
        let reportedLost = result?.warnings.contains { if case .gitTrackedFilesAlreadyMissing = $0 { return true }; return false }
        #expect(reportedLost == false)
        let refused = result?.warnings.contains { if case .iCloudDownloadFailed = $0 { return true }; return false }
        #expect(refused == true)
        let incomplete = result?.warnings.contains { if case .iCloudDownloadIncomplete(1, 1) = $0 { return true }; return false }
        #expect(incomplete == true)
    }
}
