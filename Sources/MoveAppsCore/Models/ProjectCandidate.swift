import Foundation

/// A project directory that is a candidate for transfer between roots.
public struct ProjectCandidate: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public let name: String
    public let path: URL
    public let stackTags: Set<StackTag>
    public let sizeBytes: Int64?
    /// The name of the container folder this project was unpacked from (e.g. `"NetworkTools"`),
    /// or `nil` when the project sits directly at the root. Lets the UI show where a project
    /// lives on disk even though `ProjectScanner` flattens container folders into their children.
    public let containerName: String?

    public init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        stackTags: Set<StackTag> = [],
        sizeBytes: Int64? = nil,
        containerName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.stackTags = stackTags
        self.sizeBytes = sizeBytes
        self.containerName = containerName
    }
}
