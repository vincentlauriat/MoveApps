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
}
