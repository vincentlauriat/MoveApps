import Foundation

/// A single project transfer request. Bidirectional: `from` and `to` are not assumed.
public struct TransferPlan: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let project: ProjectCandidate
    public let from: RootKind
    public let to: RootKind
    public let keepSymlink: Bool
    public let reinstallNode: Bool
    /// The folder under the destination root to place the project in (e.g. `"Outils"`), or `nil`
    /// to land it directly at the destination root. Lets a project keep — or change — its category
    /// folder across a transfer instead of being flattened to the root.
    public let destinationContainer: String?

    public init(
        id: UUID = UUID(),
        project: ProjectCandidate,
        from: RootKind,
        to: RootKind,
        keepSymlink: Bool = false,
        reinstallNode: Bool = false,
        destinationContainer: String? = nil
    ) {
        self.id = id
        self.project = project
        self.from = from
        self.to = to
        self.keepSymlink = keepSymlink
        self.reinstallNode = reinstallNode
        self.destinationContainer = destinationContainer
    }

    /// Whether `name` is a safe single-level destination folder name. Rejects anything that could
    /// escape the destination root once fed to `appendingPathComponent` + `createDirectory`:
    /// an empty (after trim) name, a path separator (`../foo`, `a/b`, `/etc`), or the `.`/`..`
    /// directory references. Mirrors `TemplateService`'s project-name rule (no `/`), extended with
    /// the `.`/`..` guards a category folder additionally needs.
    public static func isValidContainerName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("/") && trimmed != "." && trimmed != ".."
    }
}
