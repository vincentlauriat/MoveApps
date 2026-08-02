import Foundation

/// Moves a project directory, mirroring `move_dir` in move-app.sh: try a native rename
/// first, fall back to a verified copy on failure. Crucially, the copy path does **not**
/// delete the source — that decision is deferred to the pipeline until after the git
/// safety check (the `onyx` guarantee).
public struct DirectoryMover: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Native atomic rename succeeded — the source no longer exists.
        case renamed
        /// Copied via the fallback copier. Source still present and awaiting the pipeline's
        /// deletion decision. `missingPaths` carries the source-relative paths the path-set
        /// comparison found absent from the copy (empty when the copy was faithful). For a git
        /// source this is *never* hard-failed here — it is handed to the pipeline to escalate
        /// after its own git snapshot, so a critical is never pre-empted (see `move`).
        case copiedPendingDeletion(missingPaths: [String])
        case failed(reason: String)
    }

    private let copier: DirectoryCopying
    /// When true, skip the native rename and always use the fallback copier (used by tests
    /// to exercise the ditto path deterministically on a local volume).
    private let alwaysUseCopier: Bool
    private var fileManager: FileManager { .default }

    public init(
        copier: DirectoryCopying = DittoCopier(),
        alwaysUseCopier: Bool = false
    ) {
        self.copier = copier
        self.alwaysUseCopier = alwaysUseCopier
    }

    /// Moves (or, with `copyOnly`, duplicates) `source` to `destination`. `copyOnly` skips the
    /// native rename outright — a rename would remove the source, which a shared resource must
    /// keep — and reports `.copiedPendingDeletion` like any fallback copy; the pipeline is the
    /// one that decides never to delete a copy-only source.
    public func move(from source: URL, to destination: URL, copyOnly: Bool = false) async -> Outcome {
        // Never overwrite an existing destination.
        if fileManager.fileExists(atPath: destination.path) {
            return .failed(reason: "destination already exists: \(destination.path)")
        }
        try? fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !alwaysUseCopier && !copyOnly {
            do {
                try fileManager.moveItem(at: source, to: destination)
                return .renamed
            } catch {
                // Fall through to the copy path (typical iCloud FileProvider timeout).
            }
        }

        // The exit code is intentionally discarded here: the path-set comparison below is the
        // sole judge of success. `ditto` exits non-zero when the source tree contains items it
        // fundamentally cannot duplicate (a stale `.git/fsmonitor--daemon.ipc` UNIX socket left
        // behind by `core.fsmonitor`, a FIFO, a device node) even though every regular file,
        // directory, and symlink copied correctly. Trusting that exit code alone used to
        // hard-fail (or, for a git source, false-escalate the pipeline to `.critical`, stranding
        // the project in both places) a transfer that had actually fully succeeded.
        _ = await copier.copy(from: source, to: destination)

        // Structural loss net, run after every ditto fallback. Compare the *sets* of relative
        // paths, not just item counts: a count check is fooled when ditto drops one file while a
        // compensating file appears elsewhere (a stray
        // `.DS_Store`), leaving the totals equal — exactly the silent loss the `onyx` incident
        // exposed. Checked on the source: the destination's `.git` may be the very thing that
        // was lost. Special files are excluded from both sides (see `relativePaths`) since no
        // copy tool can duplicate them — their absence at the destination is not data loss.
        //
        // Responsibility split by source kind:
        //  - Non-git source has no downstream safety check, so a missing path is hard-failed here
        //    and now — it is this mover's last line of defence.
        //  - Git source is verified far more precisely by the pipeline's post-move git snapshot,
        //    which lists the exact deleted tracked paths and escalates to `.critical`. Hard-failing
        //    here would pre-empt that richer check, so we never do it for git: instead we hand the
        //    missing paths up in `.copiedPendingDeletion` and let the pipeline escalate *after* its
        //    snapshot. That also closes the git-only blind spot — untracked/gitignored files git
        //    cannot see as deletions, which neither `git status` nor a hard-fail here would catch.
        let sourcePaths = fileManager.relativePaths(at: source)
        let destPaths = fileManager.relativePaths(at: destination)
        let missing = sourcePaths.subtracting(destPaths).sorted()

        let isGitTracked = fileManager.fileExists(atPath: source.appendingPathComponent(".git").path)
        guard missing.isEmpty else {
            if !isGitTracked {
                // A real, substantive gap — clean up the partial destination this attempt created
                // so a retry sees a free slot instead of tripping the "destination already exists"
                // guard on a copy that will never complete on its own.
                try? fileManager.removeItem(at: destination)
                let shown = missing.prefix(5).joined(separator: ", ")
                let overflow = missing.count > 5 ? " et \(missing.count - 5) de plus" : ""
                return .failed(reason: "copie incomplète — chemins manquants : \(shown)\(overflow)")
            }
            return .copiedPendingDeletion(missingPaths: missing)
        }
        // ditto may have exited non-zero here (it errored solely on a special file it skipped)
        // with nothing actually missing — the path-set comparison above is what decided that,
        // not the exit code, so this is still a clean success.
        return .copiedPendingDeletion(missingPaths: [])
    }
}

extension FileManager {
    /// Every regular file, directory, and symlink under `url`, each relative to `url` — one
    /// enumeration pass, mirroring `find <dir>`. Comparing two of these sets proves a copy
    /// reproduced every source path rather than merely matching item counts.
    ///
    /// Sockets, FIFOs, and device nodes are excluded on purpose: they are transient runtime
    /// state (e.g. a stale `.git/fsmonitor--daemon.ipc` UNIX socket left by `core.fsmonitor`)
    /// that no copy tool can duplicate, so their absence at the destination is not data loss.
    func relativePaths(at url: URL) -> Set<String> {
        let root = url.standardizedFileURL.path
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [.fileResourceTypeKey],
            options: []
        ) else {
            return []
        }
        var paths: Set<String> = []
        for case let item as URL in enumerator {
            let resourceType = try? item.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType
            switch resourceType {
            case .regular, .directory, .symbolicLink, nil:
                break
            default:
                continue
            }
            let path = item.standardizedFileURL.path
            if path.hasPrefix(root + "/") {
                paths.insert(String(path.dropFirst(root.count + 1)))
            }
        }
        return paths
    }
}
