import Foundation

/// Path, relative to a template's root, of the optional post-copy init script. A template that
/// ships this file (e.g. AppKitTemplate's `Scripts/bootstrap.sh`) can rename identifiers, seed
/// git, regenerate its project, etc. right after MoveApps copies it.
public let templateInitScriptRelativePath = "Scripts/bootstrap.sh"

/// Runs a template's post-copy init script. Abstracted so tests inject a stub instead of
/// executing a real shell script.
public protocol InitScriptRunning: Sendable {
    /// Runs the init script in `directory`, passing the human-readable display name and a
    /// space-free slug. Returns the process result (exit code / captured output).
    func run(in directory: URL, displayName: String, slug: String) async -> ProcessResult
}

/// Real runner: executes `Scripts/bootstrap.sh` via `bash`.
public actor BootstrapScriptRunner: InitScriptRunning {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func run(in directory: URL, displayName: String, slug: String) async -> ProcessResult {
        let script = directory.appendingPathComponent(templateInitScriptRelativePath).path

        // A GUI app launched from Finder inherits a minimal PATH without Homebrew, yet
        // bootstrap.sh shells out to `xcodegen` (and `swift` for the icon). Prepend the usual
        // Homebrew bindirs. Run through `bash <script>` so it works even if `ditto` dropped the
        // script's executable bit. Positional args after the `-c` command map to $0/$1/$2.
        let command = #"PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" exec bash "$0" "$1" "$2""#
        return await runner.run(
            ["-c", command, script, displayName, slug],
            executable: "/bin/bash",
            currentDirectory: directory,
            timeout: .seconds(300)
        )
    }
}
