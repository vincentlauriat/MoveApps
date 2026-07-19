import Foundation

/// Moves a project directory, mirroring `move_dir` in move-app.sh: try a native rename
/// first, fall back to a verified copy on failure. Crucially, the copy path does **not**
/// delete the source — that decision is deferred to the pipeline until after the git
/// safety check (the `onyx` guarantee).
public struct DirectoryMover: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Native atomic rename succeeded — the source no longer exists.
        case renamed
        /// Copied via the fallback copier; file counts matched. Source still present and
        /// awaiting the pipeline's deletion decision.
        case copiedPendingDeletion
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

    public func move(from source: URL, to destination: URL) async -> Outcome {
        // Never overwrite an existing destination.
        if fileManager.fileExists(atPath: destination.path) {
            return .failed(reason: "destination already exists: \(destination.path)")
        }
        try? fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !alwaysUseCopier {
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

        // Structural loss net for projects with no downstream safety check. A git-tracked project
        // is verified far more precisely by the pipeline's post-move git snapshot, which lists the
        // exact deleted tracked paths and escalates the result to `.critical`; running a hard-fail
        // here too would pre-empt that richer check, so this is scoped to non-git sources — which
        // otherwise have no protection at all. Compare the *sets* of relative paths, not just item
        // counts: a count check is fooled when ditto drops one file while a compensating file
        // appears elsewhere (a stray `.DS_Store`), leaving the totals equal — exactly the silent
        // loss the `onyx` incident exposed. Checked on the source: the destination's `.git` may be
        // the very thing that was lost.
        let isGitTracked = fileManager.fileExists(atPath: source.appendingPathComponent(".git").path)
        if !isGitTracked {
            let sourcePaths = fileManager.relativePaths(at: source)
            let destPaths = fileManager.relativePaths(at: destination)
            let missing = sourcePaths.subtracting(destPaths).sorted()
            guard missing.isEmpty else {
                let shown = missing.prefix(5).joined(separator: ", ")
                let overflow = missing.count > 5 ? " et \(missing.count - 5) de plus" : ""
                return .failed(reason: "copie incomplète — chemins manquants : \(shown)\(overflow)")
            }
        }
        return .copiedPendingDeletion
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
