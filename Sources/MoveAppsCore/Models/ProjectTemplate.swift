import Foundation

/// A project template: a folder under the configured templates root whose contents are copied
/// to seed a new project. Its `name` is the folder name shown in the picker.
public struct ProjectTemplate: Sendable, Identifiable, Hashable, Codable {
    public let name: String
    public let path: URL
    public var id: URL { path }

    public init(name: String, path: URL) {
        self.name = name
        self.path = path
    }
}

/// Outcome of creating a project from a template.
public enum ProjectCreationResult: Sendable, Hashable {
    /// Project created at `url`. `gitInitialized` reflects whether a fresh `git init` succeeded
    /// (only attempted when requested and the template wasn't already a repo).
    case created(url: URL, gitInitialized: Bool)
    /// A file/folder already exists at the destination — nothing was written.
    case destinationExists(url: URL)
    /// The copy step failed; nothing usable was produced.
    case copyFailed
    /// The chosen name was empty or contained a path separator.
    case invalidName
}
