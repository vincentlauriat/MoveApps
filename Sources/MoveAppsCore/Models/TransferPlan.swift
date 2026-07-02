import Foundation

/// A single project transfer request. Bidirectional: `from` and `to` are not assumed.
public struct TransferPlan: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let project: ProjectCandidate
    public let from: RootKind
    public let to: RootKind
    public let keepSymlink: Bool
    public let reinstallNode: Bool

    public init(
        id: UUID = UUID(),
        project: ProjectCandidate,
        from: RootKind,
        to: RootKind,
        keepSymlink: Bool = false,
        reinstallNode: Bool = false
    ) {
        self.id = id
        self.project = project
        self.from = from
        self.to = to
        self.keepSymlink = keepSymlink
        self.reinstallNode = reinstallNode
    }
}
