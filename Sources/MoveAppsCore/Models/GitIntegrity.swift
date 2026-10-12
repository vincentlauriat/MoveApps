import Foundation

/// Whether a repository is internally whole, as opposed to `GitSnapshot`, which only records
/// what `git status` sees. A before/after snapshot comparison is blind to damage that was
/// already there before the move (the VisualRami incident: pack file gone, tracked files
/// missing, `git status` failing outright); this is what catches it.
public struct GitIntegrity: Sendable, Hashable, Codable {
    /// Non-empty lines printed by a failing `git fsck --connectivity-only`; `0` when it passed.
    public let fsckErrorCount: Int
    /// The first few of those lines, verbatim (git localizes them, so they are shown, never parsed).
    public let fsckSample: [String]
    /// Tracked files absent from the work tree with no iCloud placeholder standing in for them.
    public let missingTrackedFiles: [String]
    /// Tracked files absent from the work tree but present as a `.<name>.icloud` stub: never
    /// downloaded rather than lost.
    public let iCloudPendingTrackedFiles: [String]
    /// Why the check could not complete (timeout, git failure), so a check that never ran is
    /// never mistaken for a clean one. `nil` when every probe ran to completion.
    public let incompleteReason: String?

    public init(
        fsckErrorCount: Int,
        fsckSample: [String],
        missingTrackedFiles: [String],
        iCloudPendingTrackedFiles: [String],
        incompleteReason: String?
    ) {
        self.fsckErrorCount = fsckErrorCount
        self.fsckSample = fsckSample
        self.missingTrackedFiles = missingTrackedFiles
        self.iCloudPendingTrackedFiles = iCloudPendingTrackedFiles
        self.incompleteReason = incompleteReason
    }

    public var isCorrupted: Bool { fsckErrorCount > 0 }

    /// Nothing wrong found and nothing left unchecked.
    public var isHealthy: Bool {
        !isCorrupted && missingTrackedFiles.isEmpty && iCloudPendingTrackedFiles.isEmpty && incompleteReason == nil
    }
}
