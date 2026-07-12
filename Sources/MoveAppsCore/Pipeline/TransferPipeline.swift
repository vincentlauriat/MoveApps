import Foundation

/// The single entry point the UI consumes. Orchestrates one transfer and emits progressive
/// `TransferStep`s over an `AsyncStream`.
///
/// Safety-first ordering (inherited from move-app.sh and the `onyx` incident): the git
/// snapshot *after* the move is taken **before** the source is deleted, so that silently
/// lost tracked files (`D ` entries in `git status --porcelain`) escalate the result to
/// `.critical` and the source is preserved. This deviates from the bash script, which
/// deleted the source inside `move_dir` before the git check; here deletion is deferred.
public actor TransferPipeline {
    private let roots: RootLocations
    private let stackDetector: StackDetector
    private let materializer: ICloudMaterializing
    private let venvManager: VenvManager
    private let gitService: GitService
    private let mover: DirectoryMover
    private let nodeInstaller: NodeModulesInstaller
    private let symlinkVerifier: SymlinkVerifier
    private let residualScanner: ResidualPathScanner
    private let checkoutStore: CheckoutReferenceStore
    private let diskUsage: DiskUsage
    private var fileManager: FileManager { .default }

    public init(
        roots: RootLocations = .default,
        stackDetector: StackDetector = StackDetector(),
        materializer: ICloudMaterializing = FileProviderMaterializer(),
        venvManager: VenvManager = VenvManager(),
        gitService: GitService = GitService(),
        mover: DirectoryMover = DirectoryMover(),
        nodeInstaller: NodeModulesInstaller = NodeModulesInstaller(),
        symlinkVerifier: SymlinkVerifier = SymlinkVerifier(),
        residualScanner: ResidualPathScanner = ResidualPathScanner(),
        checkoutStore: CheckoutReferenceStore = CheckoutReferenceStore(),
        diskUsage: DiskUsage = DiskUsage()
    ) {
        self.roots = roots
        self.stackDetector = stackDetector
        self.materializer = materializer
        self.venvManager = venvManager
        self.gitService = gitService
        self.mover = mover
        self.nodeInstaller = nodeInstaller
        self.symlinkVerifier = symlinkVerifier
        self.residualScanner = residualScanner
        self.checkoutStore = checkoutStore
        self.diskUsage = diskUsage
    }

    private static let checkoutDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    public func run(_ plan: TransferPlan) -> AsyncStream<TransferStep> {
        AsyncStream { continuation in
            Task {
                await self.execute(plan) { continuation.yield($0) }
                continuation.finish()
            }
        }
    }

    private func execute(_ plan: TransferPlan, emit: @Sendable (TransferStep) -> Void) async {
        // Belt-and-suspenders under the UI-level hard block: a project already checked out on
        // another Mac is refused outright, without touching the filesystem.
        if let checkout = plan.project.checkoutReference {
            let when = Self.checkoutDateFormatter.string(from: checkout.takenAt)
            emit(.finished(.failed(reason: "projet déjà pris par \(checkout.hostName) le \(when)", destinationURL: nil)))
            return
        }

        let source = plan.project.path
        // Place the project under an optional category folder on the destination side, creating
        // that folder if needed — this is what lets a project keep or change its container folder
        // across a transfer instead of being flattened to the root.
        let destinationDir: URL
        if let container = plan.destinationContainer, !container.isEmpty {
            destinationDir = roots.url(for: plan.to).appendingPathComponent(container, isDirectory: true)
        } else {
            destinationDir = roots.url(for: plan.to)
        }
        let destination = destinationDir.appendingPathComponent(plan.project.name)

        // Active → Archive check-in: free the destination slot by clearing any checkout marker
        // sitting exactly at it, plus any orphaned marker filed under a different container — so
        // the "destination already exists" guard below sees a genuinely free slot.
        if plan.to == .archive {
            if checkoutStore.read(at: destination) != nil {
                checkoutStore.clear(at: destination)
            }
            checkoutStore.clearOrphans(named: plan.project.name, under: roots.url(for: .archive))
        }

        guard !fileManager.fileExists(atPath: destination.path) else {
            emit(.finished(.failed(reason: "destination already exists: \(destination.path)", destinationURL: destination)))
            return
        }

        // Ensure the (possibly new) category folder exists before the move writes into it.
        try? fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        var warnings: [TransferWarning] = []

        // 1. Stack detection.
        emit(.detectingStack)
        _ = stackDetector.detect(at: source)

        // 2. iCloud materialization (bounded).
        await materializer.materialize(at: source) { remaining in
            emit(.materializingICloud(remaining: remaining))
        }

        // 3. Capture venv state before the move (absolute paths still valid).
        let venvs = venvManager.findVenvs(in: source)
        var venvInfos: [VenvInfo] = []
        for venv in venvs {
            emit(.capturingVenvState(venv: venv))
            venvInfos.append(await venvManager.capture(venv))
        }

        // 4. Git snapshot before.
        emit(.snapshottingGitBefore)
        let before = await gitService.snapshot(source)

        // 5. Move.
        let outcome = await mover.move(from: source, to: destination)
        let wasRename: Bool
        switch outcome {
        case .renamed:
            wasRename = true
            emit(.moving(strategy: .rename))
        case .copiedPendingDeletion:
            wasRename = false
            emit(.moving(strategy: .dittoFallback))
        case .failed(let reason):
            emit(.finished(.failed(reason: reason, destinationURL: nil, warnings: warnings)))
            return
        }

        // 6. Git snapshot after — BEFORE any source deletion (the onyx guarantee).
        emit(.verifyingGitAfter)
        let after = await gitService.snapshot(destination)
        if before.isRepo {
            let newlyDeleted = after.deletedPaths.filter { !before.deletedPaths.contains($0) }
            if !newlyDeleted.isEmpty {
                warnings.append(.gitDeletedFilesDetected(paths: newlyDeleted))
            } else if before.dirtyCount != after.dirtyCount {
                warnings.append(.gitDirtyCountChanged(before: before.dirtyCount, after: after.dirtyCount))
            }
        }

        let isCritical = warnings.contains { $0.isCritical }

        // 7. Source deletion decision. Rename already moved the source; the copy path
        //    deletes only when the git check is clean.
        var sourceDeleted: Bool
        if wasRename {
            sourceDeleted = true
        } else if isCritical {
            sourceDeleted = false // preserve for inspection
        } else {
            try? fileManager.removeItem(at: source)
            sourceDeleted = !fileManager.fileExists(atPath: source.path)
        }

        // 7b. Archive → Active check-out: once the source slot is confirmed gone (and the onyx
        //     invariant held — no critical loss), leave a marker at the original path so another
        //     Mac sees it as "taken", not free. A write failure is surfaced, never swallowed:
        //     the "re-taken by mistake" hole reopens if this fails silently.
        if plan.from == .archive && sourceDeleted && !isCritical {
            emit(.measuringSize)
            let size = await diskUsage.sizeBytes(of: destination)
            do {
                try checkoutStore.write(at: source, destinationPath: destination.path, sizeBytes: size)
            } catch {
                warnings.append(.checkoutReferenceWriteFailed(reason: error.localizedDescription))
            }
        }

        // 8. Recreate venvs at the new location.
        for info in venvInfos {
            let relative = relativePath(of: info.path, under: source)
            let newVenv = destination.appendingPathComponent(relative)
            emit(.recreatingVenv(venv: newVenv))
            switch await venvManager.recreate(info, at: newVenv) {
            case .recreated:
                break
            case .recreatedEmpty, .creationFailed:
                warnings.append(.venvRecreatedEmpty(venv: newVenv))
            case .partialInstall(let failed):
                warnings.append(.venvPartialInstall(venv: newVenv, failedPackages: failed))
            }
        }

        // 9. Optional node_modules reinstall.
        if plan.reinstallNode {
            emit(.reinstallingNodeModules)
            if case .failed(let reason) = await nodeInstaller.reinstall(in: destination) {
                warnings.append(.nodeReinstallFailed(reason: reason))
            }
        }

        // 10. Optional compatibility symlink (only when the old path is now free).
        if plan.keepSymlink && sourceDeleted {
            emit(.creatingCompatibilitySymlink)
            try? fileManager.createSymbolicLink(at: source, withDestinationURL: destination)
        }

        // 11. Residual old-path references.
        emit(.scanningResidualPaths)
        let residual = residualScanner.scan(root: destination, forPath: source.path)
        if !residual.isEmpty {
            warnings.append(.residualPathReferences(files: residual))
        }

        // 12. Broken / cross-project symlinks.
        emit(.scanningSymlinks)
        warnings.append(contentsOf: symlinkVerifier.scan(root: destination))

        emit(.finished(.make(warnings: warnings, sourceDeleted: sourceDeleted, destinationURL: destination)))
    }

    private func relativePath(of url: URL, under base: URL) -> String {
        let urlPath = url.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path
        if urlPath == basePath { return "" }
        if urlPath.hasPrefix(basePath + "/") {
            return String(urlPath.dropFirst(basePath.count + 1))
        }
        return url.lastPathComponent
    }
}
