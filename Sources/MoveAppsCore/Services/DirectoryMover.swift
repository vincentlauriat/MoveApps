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

        let sourceCount = fileManager.recursiveItemCount(at: source)
        let destCount = fileManager.recursiveItemCount(at: destination)
        guard sourceCount == destCount else {
            return .failed(reason: "incomplete copy (source: \(sourceCount) items, destination: \(destCount) items)")
        }
        return .copiedPendingDeletion
    }
}

extension FileManager {
    /// Counts the directory itself plus all descendants, mirroring `find <dir> | wc -l`.
    func recursiveItemCount(at url: URL) -> Int {
        guard let enumerator = enumerator(at: url, includingPropertiesForKeys: nil, options: []) else {
            return fileExists(atPath: url.path) ? 1 : 0
        }
        var count = 1 // the root itself
        for case _ as URL in enumerator {
            count += 1
        }
        return count
    }
}
