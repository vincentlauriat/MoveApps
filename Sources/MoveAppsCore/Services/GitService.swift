import Foundation

/// Captures git state via `Process` calls to `/usr/bin/git` (no libgit2 dependency).
public actor GitService {
    private let runner: ProcessRunner
    private let gitPath = "/usr/bin/git"
    private var fileManager: FileManager { .default }

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func isRepository(_ directory: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path, isDirectory: &isDir)
            && isDir.boolValue
    }

    public func snapshot(_ directory: URL) async -> GitSnapshot {
        guard isRepository(directory) else { return .none }

        let head = await revParse(["HEAD"], in: directory)
        let branch = await revParse(["--abbrev-ref", "HEAD"], in: directory)
        let status = await runner.run(
            ["-C", directory.path, "status", "--porcelain"],
            executable: gitPath,
            timeout: .seconds(25)
        )
        let entries = GitStatusEntry.parse(status.standardOutput)
        let deleted = entries.filter { $0.isDeleted }.map { $0.path }
        return GitSnapshot(branch: branch, head: head, dirtyCount: entries.count, deletedPaths: deleted)
    }

    /// Initializes a fresh git repository at `directory` (`git init`). Returns whether it
    /// succeeded. A no-op-ish call on a directory that is already a repo still returns `true`
    /// (git re-initializing is safe), but callers generally guard with `isRepository` first.
    public func initRepository(_ directory: URL) async -> Bool {
        let result = await runner.run(
            ["-C", directory.path, "init"],
            executable: gitPath,
            timeout: .seconds(20)
        )
        return result.didSucceed
    }

    private func revParse(_ args: [String], in directory: URL) async -> String? {
        let result = await runner.run(
            ["-C", directory.path, "rev-parse"] + args,
            executable: gitPath,
            timeout: .seconds(20)
        )
        let value = result.trimmedOutput
        return result.didSucceed && !value.isEmpty ? value : nil
    }
}
