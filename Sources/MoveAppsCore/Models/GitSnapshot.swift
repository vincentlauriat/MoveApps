import Foundation

/// A point-in-time snapshot of a git repository's state (branch, HEAD, dirty count,
/// deleted paths), captured before and after a move to detect corruption.
public struct GitSnapshot: Sendable, Hashable, Codable {
    public let branch: String?
    public let head: String?
    public let dirtyCount: Int
    public let deletedPaths: [String]
    /// `false` when `git status` itself failed (e.g. "bad tree object HEAD" on a repo whose pack
    /// is gone): the empty `dirtyCount`/`deletedPaths` then mean "unknown", not "clean".
    public let statusReadable: Bool

    public init(branch: String?, head: String?, dirtyCount: Int, deletedPaths: [String], statusReadable: Bool = true) {
        self.branch = branch
        self.head = head
        self.dirtyCount = dirtyCount
        self.deletedPaths = deletedPaths
        self.statusReadable = statusReadable
    }

    /// A snapshot of a non-git directory.
    public static let none = GitSnapshot(branch: nil, head: nil, dirtyCount: 0, deletedPaths: [])

    public var isRepo: Bool { head != nil }
}
