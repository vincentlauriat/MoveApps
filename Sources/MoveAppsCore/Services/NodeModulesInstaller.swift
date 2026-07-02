import Foundation

/// Optionally reinstalls node_modules using the package manager matching the lockfile.
public struct NodeModulesInstaller: Sendable {
    public enum Outcome: Sendable, Equatable {
        case skipped
        case installed
        case failed(reason: String)
    }

    private let runner: ProcessRunner
    private var fileManager: FileManager { .default }

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func reinstall(in directory: URL) async -> Outcome {
        let tool: String
        if fileManager.fileExists(atPath: directory.appendingPathComponent("pnpm-lock.yaml").path) {
            tool = "pnpm"
        } else if fileManager.fileExists(atPath: directory.appendingPathComponent("yarn.lock").path) {
            tool = "yarn"
        } else if fileManager.fileExists(atPath: directory.appendingPathComponent("package.json").path) {
            tool = "npm"
        } else {
            return .skipped
        }

        try? fileManager.removeItem(at: directory.appendingPathComponent("node_modules"))

        // Resolve the tool through PATH via `/usr/bin/env`.
        let result = await runner.run(
            [tool, "install"],
            executable: "/usr/bin/env",
            currentDirectory: directory,
            timeout: .seconds(600)
        )
        return result.didSucceed ? .installed : .failed(reason: "\(tool) install failed")
    }
}
