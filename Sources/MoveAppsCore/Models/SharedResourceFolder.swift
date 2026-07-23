import Foundation

/// Root-level folders that are shared resources rather than projects — e.g. `Templates`, which
/// both roots reference by relative path (`Templates/Scripts/…`) and which must therefore exist
/// on every Mac and in every root at once. A transfer of such a folder *copies* it instead of
/// moving it: the source stays in place, no checkout lock is taken, and the source is never
/// deleted.
public enum SharedResourceFolder {
    /// Folder names treated as shared resources when found at the top level of a root.
    public static let names: Set<String> = ["Templates"]

    /// Whether a top-level entry name designates a shared resource folder.
    public static func isSharedName(_ name: String) -> Bool {
        names.contains(name)
    }

    /// Whether a candidate is a shared resource: a top-level folder (no container) whose name
    /// matches. A nested folder that merely happens to be called `Templates` inside a project
    /// container keeps the normal move semantics.
    public static func isShared(_ candidate: ProjectCandidate) -> Bool {
        candidate.containerName == nil && isSharedName(candidate.name)
    }
}
