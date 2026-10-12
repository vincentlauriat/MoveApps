import Foundation

/// Captures git state via `Process` calls to `/usr/bin/git` (no libgit2 dependency).
public actor GitService {
    private let runner: ProcessRunner
    private let gitPath = "/usr/bin/git"
    private let fsckTimeout: Duration
    private var fileManager: FileManager { .default }

    /// `fsckTimeout` bounds the integrity check: a pack still dataless in iCloud would make fsck
    /// block on a download, and that must end as an incomplete check, never a hang.
    public init(runner: ProcessRunner = ProcessRunner(), fsckTimeout: Duration = .seconds(60)) {
        self.runner = runner
        self.fsckTimeout = fsckTimeout
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
        return GitSnapshot(branch: branch, head: head, dirtyCount: entries.count, deletedPaths: deleted,
                           statusReadable: status.didSucceed)
    }

    /// Checks that the repository at `directory` is whole: every object reachable from a ref is
    /// present, and every tracked file is in the work tree. Returns `nil` for a non-repo.
    ///
    /// Gated on the `.git` directory, not on `snapshot.isRepo`: a repo with damaged refs has no
    /// resolvable HEAD and is exactly the one that must not be skipped.
    ///
    /// `--connectivity-only` checks that every object referenced from a ref exists (blobs
    /// included) without inflating and re-hashing them, so it catches a missing or truncated
    /// pack — iCloud's failure modes — at a fraction of a full fsck's cost (measured: 0.1–0.2 s
    /// vs 2.8–3 s on a 102 MiB pack, and the full check grows with the pack). It does not catch
    /// silent bit rot inside a pack that still matches its index; nothing here would cause that.
    public func checkIntegrity(_ directory: URL) async -> GitIntegrity? {
        guard isRepository(directory) else { return nil }
        var incomplete: [String] = []

        let fsck = await runner.run(
            ["-C", directory.path, "fsck", "--connectivity-only", "--no-progress", "--no-dangling"],
            executable: gitPath,
            timeout: fsckTimeout
        )
        var fsckErrors: [String] = []
        if fsck.timedOut {
            incomplete.append("git fsck interrompu après \(fsckTimeout.components.seconds) s")
        } else if fsck.exitCode != 0 {
            // Decided on the exit code alone: a healthy repo may still print notices. The lines are
            // counted and sampled, not interpreted — git translates them.
            fsckErrors = (fsck.standardError + "\n" + fsck.standardOutput)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if fsckErrors.isEmpty { fsckErrors = ["git fsck a échoué (code \(fsck.exitCode))"] }
        }

        // The index alone says what is tracked; unlike `git status`, this still works when the
        // object database is broken. `-z` keeps non-ASCII paths unquoted.
        let listing = await runner.run(
            ["-C", directory.path, "ls-files", "--deleted", "-z"],
            executable: gitPath,
            timeout: .seconds(25)
        )
        var missing: [String] = []
        var pending: [String] = []
        if listing.didSucceed {
            let paths = Set(listing.standardOutput.split(separator: "\0", omittingEmptySubsequences: true).map(String.init))
            for path in paths.sorted() {
                if hasICloudStub(for: path, in: directory) {
                    pending.append(path)
                } else {
                    missing.append(path)
                }
            }
        } else {
            let reason = listing.timedOut ? "délai dépassé" : listing.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            incomplete.append("git ls-files a échoué : \(reason)")
        }

        return GitIntegrity(
            fsckErrorCount: fsckErrors.count,
            fsckSample: Array(fsckErrors.prefix(5)),
            missingTrackedFiles: missing,
            iCloudPendingTrackedFiles: pending,
            incompleteReason: incomplete.isEmpty ? nil : incomplete.joined(separator: " ; ")
        )
    }

    /// iCloud stands a dematerialized `name` in for itself as a hidden `.name.icloud` sibling.
    private func hasICloudStub(for relativePath: String, in directory: URL) -> Bool {
        let file = directory.appendingPathComponent(relativePath)
        let stub = file.deletingLastPathComponent().appendingPathComponent("." + file.lastPathComponent + ".icloud")
        return fileManager.fileExists(atPath: stub.path)
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
