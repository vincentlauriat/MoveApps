import Foundation
import Testing
@testable import MoveAppsCore

// Serialized: each test spawns real git subprocesses and copies trees; running them in
// parallel saturates the concurrency pool via the synchronous git fixtures.
@Suite("TransferPipeline", .serialized)
struct TransferPipelineTests {
    /// Builds a fixture: an archive root containing a clean git repo, and an empty active
    /// root to move it into. Returns (plan, roots, source, destination).
    private func makeScenario(
        repoName: String = "onyx",
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

    // MARK: - The onyx reproduction (most important test in Phase 1)

    @Test("onyx: silently dropped tracked file is caught as critical and source is preserved")
    func onyxCriticalDetection() async {
        let scenario = makeScenario(files: [
            "src/deep/keep.swift": "let answer = 42\n",
            "README.md": "onyx\n",
        ])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        // Copier drops the tracked file yet keeps the file count equal (adds a .DS_Store),
        // exactly the condition that fooled the count check in production.
        let mover = DirectoryMover(
            copier: FaultInjectingCopier(drop: "src/deep/keep.swift"),
            alwaysUseCopier: true
        )
        let pipeline = TransferPipeline(roots: scenario.roots, mover: mover)

        let result = await pipeline.finalResult(for: scenario.plan)

        #expect(result?.status == .critical)
        let deleted = result?.warnings.compactMap { warning -> [String]? in
            if case .gitDeletedFilesDetected(let paths) = warning { return paths }
            return nil
        }
        #expect(deleted == [["src/deep/keep.swift"]])

        // The source MUST NOT have been deleted.
        #expect(result?.sourceDeleted == false)
        #expect(FileManager.default.fileExists(atPath: scenario.source.path))
    }

    // MARK: - Happy path

    @Test("happy path: native rename yields ok and removes the source")
    func happyPathRename() async {
        let scenario = makeScenario(repoName: "clean-project", files: [
            "main.swift": "print(\"hi\")\n",
        ])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        let pipeline = TransferPipeline(roots: scenario.roots)
        let result = await pipeline.finalResult(for: scenario.plan)

        #expect(result?.status == .ok)
        #expect(result?.warnings.isEmpty == true)
        #expect(result?.sourceDeleted == true)
        #expect(!FileManager.default.fileExists(atPath: scenario.source.path))
        #expect(FileManager.default.fileExists(atPath: scenario.destination.path))
    }

    // MARK: - Benign vs critical

    @Test("benign modification changes dirty count only -> warning, source removed")
    func benignDirtyCountChange() async {
        let scenario = makeScenario(repoName: "modified-project", files: [
            "config.txt": "value=1\n",
        ])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        // Copier modifies a tracked file (M), never deletes -> benign.
        let mover = DirectoryMover(
            copier: FaultInjectingCopier(modify: "config.txt"),
            alwaysUseCopier: true
        )
        let pipeline = TransferPipeline(roots: scenario.roots, mover: mover)
        let result = await pipeline.finalResult(for: scenario.plan)

        #expect(result?.status == .warning)
        let dirtyChanged = result?.warnings.contains { warning in
            if case .gitDirtyCountChanged = warning { return true }
            return false
        }
        #expect(dirtyChanged == true)
        let hasDeleted = result?.warnings.contains { warning in
            if case .gitDeletedFilesDetected = warning { return true }
            return false
        }
        #expect(hasDeleted == false)
        // Not critical, so the source is removed after the verified copy.
        #expect(result?.sourceDeleted == true)
    }

    // MARK: - Guard rails

    @Test("refuses to overwrite an existing destination")
    func refusesExistingDestination() async {
        let scenario = makeScenario(repoName: "collide", files: ["a.txt": "a\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }
        // Pre-create the destination.
        try? FileManager.default.createDirectory(at: scenario.destination, withIntermediateDirectories: true)

        let pipeline = TransferPipeline(roots: scenario.roots)
        let result = await pipeline.finalResult(for: scenario.plan)

        #expect(result?.status == .failed)
        #expect(result?.sourceDeleted == false)
        #expect(FileManager.default.fileExists(atPath: scenario.source.path))
    }
}
