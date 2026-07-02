import Foundation

/// A project directory that is a candidate for transfer between roots.
public struct ProjectCandidate: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public let name: String
    public let path: URL
    public let stackTags: Set<StackTag>
    public let sizeBytes: Int64?

    public init(id: UUID = UUID(), name: String, path: URL, stackTags: Set<StackTag> = [], sizeBytes: Int64? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.stackTags = stackTags
        self.sizeBytes = sizeBytes
    }
}
