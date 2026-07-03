import Foundation

/// Lists project templates under a templates root and creates new projects from them.
///
/// A template is simply a direct subdirectory of the templates root; creating a project copies
/// that subdirectory's tree (via the same `DirectoryCopying`/`ditto` path the transfer pipeline
/// uses, so iCloud materialization and large trees are handled) to a new folder under a
/// destination root, optionally seeding a fresh git repo.
public actor TemplateService {
    private let copier: DirectoryCopying
    private let git: GitService
    private var fileManager: FileManager { .default }

    public init(copier: DirectoryCopying = DittoCopier(), git: GitService = GitService()) {
        self.copier = copier
        self.git = git
    }

    /// Templates available under `root`, sorted by name. Returns an empty list if the root
    /// doesn't exist yet (e.g. the user never created a `.templates` folder). `nonisolated`:
    /// pure filesystem read, touches no actor state, so callers needn't hop onto the actor.
    public nonisolated func templates(in root: URL) -> [ProjectTemplate] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
            .map { ProjectTemplate(name: $0.lastPathComponent, path: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Creates a project named `name` under `destinationRoot` by copying `template`. Refuses an
    /// empty or path-separator-bearing name, and never overwrites an existing destination.
    /// When `gitInit` is true and the copied tree isn't already a git repo, runs `git init`.
    public func createProject(
        named name: String,
        from template: ProjectTemplate,
        destinationRoot: URL,
        gitInit: Bool
    ) async -> ProjectCreationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return .invalidName }

        let destination = destinationRoot.appendingPathComponent(trimmed, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            return .destinationExists(url: destination)
        }

        // Ensure the destination root exists (first-run: templates configured, root not yet made).
        try? fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let copied = await copier.copy(from: template.path, to: destination)
        guard copied, fileManager.fileExists(atPath: destination.path) else {
            return .copyFailed
        }

        var gitInitialized = false
        if gitInit, !(await git.isRepository(destination)) {
            gitInitialized = await git.initRepository(destination)
        }
        return .created(url: destination, gitInitialized: gitInitialized)
    }
}
