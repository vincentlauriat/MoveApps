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
    private let scriptRunner: InitScriptRunning
    private var fileManager: FileManager { .default }

    public init(
        copier: DirectoryCopying = DittoCopier(),
        git: GitService = GitService(),
        scriptRunner: InitScriptRunning = BootstrapScriptRunner()
    ) {
        self.copier = copier
        self.git = git
        self.scriptRunner = scriptRunner
    }

    /// A space-free, filesystem/Xcode-friendly slug derived from a project name
    /// (`"My New App"` → `"MyNewApp"`). Falls back to `"App"` if nothing usable remains.
    static func slug(from name: String) -> String {
        let scalars = name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let slug = String(String.UnicodeScalarView(scalars))
        return slug.isEmpty ? "App" : slug
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
    ///
    /// After the copy, if the template ships `Scripts/bootstrap.sh` and `runInitScript` is true,
    /// that script is run (it renames identifiers, regenerates the project and seeds git). In that
    /// case the script owns git, so no separate `git init` is attempted. Otherwise, when `gitInit`
    /// is true and the copy isn't already a repo, a plain `git init` is run.
    public func createProject(
        named name: String,
        from template: ProjectTemplate,
        destinationRoot: URL,
        gitInit: Bool,
        runInitScript: Bool = true
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

        // Post-copy init script (opt-in), present only in templates that ship it.
        let hasScript = fileManager.fileExists(
            atPath: destination.appendingPathComponent(templateInitScriptRelativePath).path)
        var initScript: InitScriptOutcome = .none
        if hasScript {
            if runInitScript {
                let result = await scriptRunner.run(
                    in: destination, displayName: trimmed, slug: Self.slug(from: trimmed))
                initScript = result.didSucceed ? .ran : .failed
            } else {
                initScript = .skipped
            }
        }

        // git: the init script seeds its own repo; only fall back to a plain `git init` when the
        // script didn't run.
        var gitInitialized = false
        if initScript == .ran {
            gitInitialized = await git.isRepository(destination)
        } else if gitInit, !(await git.isRepository(destination)) {
            gitInitialized = await git.initRepository(destination)
        }

        return .created(url: destination, gitInitialized: gitInitialized, initScript: initScript)
    }
}
