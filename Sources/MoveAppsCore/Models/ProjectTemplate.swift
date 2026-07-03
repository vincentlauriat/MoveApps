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

/// Outcome of running a template's optional post-copy init script.
public enum InitScriptOutcome: Sendable, Hashable {
    /// The template ships no `Scripts/bootstrap.sh`.
    case none
    /// A script is present but the caller opted out of running it.
    case skipped
    /// The script ran and exited 0.
    case ran
    /// The script ran but failed (non-zero exit or timeout). The copy is still on disk.
    case failed
}

/// Outcome of creating a project from a template.
public enum ProjectCreationResult: Sendable, Hashable {
    /// Project created at `url`. `gitInitialized` reflects whether git was seeded (by a fresh
    /// `git init` or by the init script). `initScript` reports the post-copy script outcome.
    case created(url: URL, gitInitialized: Bool, initScript: InitScriptOutcome)
    /// A file/folder already exists at the destination — nothing was written.
    case destinationExists(url: URL)
    /// The copy step failed; nothing usable was produced.
    case copyFailed
    /// The chosen name was empty or contained a path separator.
    case invalidName
}
