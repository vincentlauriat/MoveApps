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

        let copied = await copier.copy(from: source, to: destination)
        guard copied else {
            return .failed(reason: "copy failed")
        }

        // Structural loss net, run after every ditto fallback. Compare the *sets* of relative
        // paths, not just item counts: a count check is fooled when ditto drops one file while a
        // compensating file appears elsewhere (a stray `.DS_Store`), leaving the totals equal —
        // exactly the silent loss the `onyx` incident exposed. Checked on the source: the
        // destination's `.git` may be the very thing that was lost.
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
        if !isGitTracked, !missing.isEmpty {
            let shown = missing.prefix(5).joined(separator: ", ")
            let overflow = missing.count > 5 ? " et \(missing.count - 5) de plus" : ""
            return .failed(reason: "copie incomplète — chemins manquants : \(shown)\(overflow)")
        }
        return .copiedPendingDeletion(missingPaths: missing)
    }
}

extension FileManager {
    /// Every path under `url` (files and directories alike), each relative to `url` — one
    /// enumeration pass, mirroring `find <dir>`. Comparing two of these sets proves a copy
    /// reproduced every source path rather than merely matching item counts.
    func relativePaths(at url: URL) -> Set<String> {
        let root = url.standardizedFileURL.path
        guard let enumerator = enumerator(at: url, includingPropertiesForKeys: nil, options: []) else {
            return []
        }
        var paths: Set<String> = []
        for case let item as URL in enumerator {
            let path = item.standardizedFileURL.path
            if path.hasPrefix(root + "/") {
                paths.insert(String(path.dropFirst(root.count + 1)))
            }
        }
        return paths
    }
}
