import Foundation

/// A single line of `git status --porcelain` output.
///
/// Porcelain v1 format is `XY <path>` where `X` is the index status and `Y` is the
/// worktree status (each a single character), followed by a space and the path.
/// Renames appear as `R  old -> new`.
public struct GitStatusEntry: Sendable, Hashable {
    public let path: String
    public let indexStatus: Character
    public let worktreeStatus: Character

    public init(path: String, indexStatus: Character, worktreeStatus: Character) {
        self.path = path
        self.indexStatus = indexStatus
        self.worktreeStatus = worktreeStatus
    }

    /// True when either side marks the file as deleted (`D`). This is the `onyx`
    /// safety signal: silently-lost tracked files show up here.
    public var isDeleted: Bool {
        indexStatus == "D" || worktreeStatus == "D"
    }

    public static func parse(_ porcelainOutput: String) -> [GitStatusEntry] {
        var entries: [GitStatusEntry] = []
        for rawLine in porcelainOutput.split(separator: "\n", omittingEmptySubsequences: true) {
            let chars = Array(rawLine)
            // Need at least "XY " + one path character.
            guard chars.count >= 4 else { continue }
            let index = chars[0]
            let worktree = chars[1]
            let path = String(chars[3...])
            entries.append(GitStatusEntry(path: path, indexStatus: index, worktreeStatus: worktree))
        }
        return entries
    }
}
