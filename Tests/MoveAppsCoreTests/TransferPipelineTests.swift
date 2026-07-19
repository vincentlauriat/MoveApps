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

    /// The onyx hole that git alone cannot close: the copier drops a gitignored working-tree
    /// file (a local `.env`), so `git status` on the destination reports no deletion — yet the
    /// file is gone. The mover's path-set comparison must surface it and the pipeline must
    /// escalate to `.critical`, preserving the source, just as for a tracked loss.
    @Test("gitignored file silently dropped in copy is caught as critical and source is preserved")
    func untrackedLossDetection() async {
        let scenario = makeScenario(files: [
            ".gitignore": "secret.env\n",
            "secret.env": "SECRET=1\n",
            "README.md": "onyx\n",
        ])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        // Drops the gitignored `secret.env` yet keeps totals equal (adds a .DS_Store). Git sees
        // no deletion (the file was never tracked); only the path-set check can catch it.
        let mover = DirectoryMover(
            copier: FaultInjectingCopier(drop: "secret.env"),
            alwaysUseCopier: true
        )
        let pipeline = TransferPipeline(roots: scenario.roots, mover: mover)

        let result = await pipeline.finalResult(for: scenario.plan)

        #expect(result?.status == .critical)
        // The source MUST NOT have been deleted.
        #expect(result?.sourceDeleted == false)
        #expect(FileManager.default.fileExists(atPath: scenario.source.appendingPathComponent("secret.env").path))
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
        // The original content is gone, but the Archive slot now holds a checkout marker.
        #expect(!FileManager.default.fileExists(atPath: scenario.source.appendingPathComponent("main.swift").path))
        #expect(CheckoutReferenceStore().read(at: scenario.source) != nil)
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

    // MARK: - Destination folder

    @Test("places the project under a (newly created) destination container folder")
    func placesIntoDestinationContainer() async {
        let scenario = makeScenario(repoName: "X", files: ["main.swift": "print(1)\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        // Move X into a "Outils" folder on the active side that does not exist yet.
        let plan = TransferPlan(
            project: scenario.plan.project,
            from: .archive,
            to: .active,
            destinationContainer: "Outils"
        )
        let pipeline = TransferPipeline(roots: scenario.roots)
        let result = await pipeline.finalResult(for: plan)

        let landed = scenario.roots.active
            .appendingPathComponent("Outils", isDirectory: true)
            .appendingPathComponent("X", isDirectory: true)
        #expect(result?.status == .ok)
        #expect(result?.destinationURL?.standardizedFileURL == landed.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: landed.appendingPathComponent("main.swift").path))
        // The flat destination must NOT have been used.
        #expect(!FileManager.default.fileExists(atPath: scenario.destination.appendingPathComponent("main.swift").path))
    }

    // MARK: - Checkout markers

    /// Builds an Active → Archive fixture: a clean repo in the active root and an (empty) archive
    /// root to check it into. Returns (roots, source, archiveRoot, cleanup).
    private func makeCheckInScenario(
        repoName: String,
        files: [String: String]
    ) -> (roots: RootLocations, source: URL, archiveRoot: URL, cleanup: URL) {
        let tmp = Fixture.makeTempDir()
        let archiveRoot = tmp.appendingPathComponent("archive")
        let activeRoot = tmp.appendingPathComponent("active")
        try? FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        let source = activeRoot.appendingPathComponent(repoName)
        Fixture.makeCleanRepo(at: source, files: files)
        return (RootLocations(active: activeRoot, archive: archiveRoot), source, archiveRoot, tmp)
    }

    @Test("Archive → Active leaves a valid checkout marker at the original slot")
    func archiveToActiveWritesMarker() async throws {
        let scenario = makeScenario(repoName: "TakeMe", files: ["main.swift": "print(1)\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        let pipeline = TransferPipeline(roots: scenario.roots)
        let result = await pipeline.finalResult(for: scenario.plan)
        #expect(result?.status == .ok)

        let marker = CheckoutReferenceStore().read(at: scenario.source)
        #expect(marker != nil)
        #expect(marker?.hostName == CheckoutReferenceStore.sanitize(CheckoutReferenceStore.currentHostName()))
        #expect(marker?.destinationPath == scenario.destination.standardizedFileURL.path)
    }

    @Test("Active → Archive into a marked slot clears the marker and round-trips the content")
    func activeToArchiveClearsMarkerAndRoundTrips() async throws {
        let scenario = makeCheckInScenario(repoName: "RoundTrip", files: [
            "src/keep.swift": "let x = 1\n", "README.md": "RoundTrip\n",
        ])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        let destination = scenario.archiveRoot.appendingPathComponent("RoundTrip")
        try CheckoutReferenceStore().write(at: destination, destinationPath: scenario.source.path, sizeBytes: 123)

        let project = ProjectCandidate(name: "RoundTrip", path: scenario.source, stackTags: [.git])
        let plan = TransferPlan(project: project, from: .active, to: .archive)
        let pipeline = TransferPipeline(roots: scenario.roots)
        let result = await pipeline.finalResult(for: plan)

        #expect(result?.status == .ok)
        #expect(CheckoutReferenceStore().read(at: destination) == nil)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("src/keep.swift").path))
        #expect(!FileManager.default.fileExists(atPath: scenario.source.path))
    }

    @Test("Active → Archive clears an orphaned marker filed under a different container")
    func checkInClearsOrphanInOtherContainer() async throws {
        let scenario = makeCheckInScenario(repoName: "Widget", files: ["main.swift": "print(1)\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        // The project was taken from Outils/Widget but is returned to the archive root.
        let orphan = scenario.archiveRoot.appendingPathComponent("Outils/Widget")
        try CheckoutReferenceStore().write(at: orphan, destinationPath: scenario.source.path, sizeBytes: nil)

        let project = ProjectCandidate(name: "Widget", path: scenario.source, stackTags: [.git])
        let plan = TransferPlan(project: project, from: .active, to: .archive)
        let pipeline = TransferPipeline(roots: scenario.roots)
        let result = await pipeline.finalResult(for: plan)

        #expect(result?.status == .ok)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: scenario.archiveRoot.appendingPathComponent("Widget/main.swift").path))
    }

    @Test("refuses a plan against an already-checked-out project without touching disk")
    func refusesCheckedOutProject() async {
        let scenario = makeScenario(repoName: "Locked", files: ["main.swift": "print(1)\n"])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        let reference = CheckoutReference(hostName: "OtherMac", takenAt: Date(), destinationPath: nil, sizeBytes: nil)
        let locked = ProjectCandidate(name: "Locked", path: scenario.source, stackTags: [.git], checkoutReference: reference)
        let plan = TransferPlan(project: locked, from: .archive, to: .active)

        let pipeline = TransferPipeline(roots: scenario.roots)
        let result = await pipeline.finalResult(for: plan)

        #expect(result?.status == .failed)
        #expect(result?.failureReason?.contains("OtherMac") == true)
        // Disk untouched: destination never created, source still whole.
        #expect(!FileManager.default.fileExists(atPath: scenario.destination.path))
        #expect(FileManager.default.fileExists(atPath: scenario.source.appendingPathComponent("main.swift").path))
    }

    @Test("critical (onyx) path writes no checkout marker and preserves the source intact")
    func criticalPathWritesNoMarker() async {
        let scenario = makeScenario(files: [
            "src/deep/keep.swift": "let answer = 42\n", "README.md": "onyx\n",
        ])
        defer { try? FileManager.default.removeItem(at: scenario.cleanup) }

        let mover = DirectoryMover(
            copier: FaultInjectingCopier(drop: "src/deep/keep.swift"),
            alwaysUseCopier: true
        )
        let pipeline = TransferPipeline(roots: scenario.roots, mover: mover)
        let result = await pipeline.finalResult(for: scenario.plan)

        #expect(result?.status == .critical)
        #expect(CheckoutReferenceStore().read(at: scenario.source) == nil)
        // The source is untouched — still the real project, not a checkout stub.
        #expect(FileManager.default.fileExists(atPath: scenario.source.appendingPathComponent("src/deep/keep.swift").path))
    }
}
