import Foundation

/// Detects, captures and recreates Python virtual environments.
/// A venv is identified by a `pyvenv.cfg` file (mirrors `find_venvs`), **not** by folder
/// name — a directory named `venv`/`.venv` without a `pyvenv.cfg` is not a venv.
public struct VenvManager: Sendable {
    public enum RecreateOutcome: Sendable, Equatable {
        case recreated
        case recreatedEmpty
        case partialInstall(failedPackages: [String])
        case creationFailed
    }

    private let runner: ProcessRunner
    private let pythonExecutable: String
    private var fileManager: FileManager { .default }

    public init(
        runner: ProcessRunner = ProcessRunner(),
        pythonExecutable: String = "/usr/bin/env"
    ) {
        self.runner = runner
        self.pythonExecutable = pythonExecutable
    }

    /// Directories containing a `pyvenv.cfg` at depth 1...maxDepth below `directory`.
    public func findVenvs(in directory: URL, maxDepth: Int = 4) -> [URL] {
        var result: [URL] = []
        func walk(_ url: URL, depth: Int) {
            guard depth <= maxDepth else { return }
            guard let items = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { return }
            for item in items {
                if item.lastPathComponent == "pyvenv.cfg" {
                    result.append(url)
                }
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory && depth < maxDepth {
                    walk(item, depth: depth + 1)
                }
            }
        }
        walk(directory, depth: 1)
        return result
    }

    /// Captures `pip freeze` for a venv while its absolute paths are still valid.
    public func capture(_ venv: URL) async -> VenvInfo {
        let pip = venv.appendingPathComponent("bin/pip")
        guard fileManager.isExecutableFile(atPath: pip.path) else {
            return VenvInfo(path: venv, packages: [])
        }
        let result = await runner.run(["freeze"], executable: pip.path, timeout: .seconds(30))
        let packages = result.outputLines.filter { !$0.isEmpty }
        return VenvInfo(path: venv, packages: packages)
    }

    /// Recreates a venv at its new location and reinstalls the captured packages.
    /// A venv's `bin/*` scripts hard-code an absolute shebang, so it cannot be relocated
    /// as-is — it must be rebuilt in place.
    public func recreate(_ info: VenvInfo, at newVenv: URL) async -> RecreateOutcome {
        try? fileManager.removeItem(at: newVenv)

        let create = await runner.run(
            ["python3", "-m", "venv", newVenv.path],
            executable: pythonExecutable,
            timeout: .seconds(120)
        )
        guard create.didSucceed else { return .creationFailed }

        guard !info.packages.isEmpty else { return .recreatedEmpty }

        let pip = newVenv.appendingPathComponent("bin/pip")

        // Fast path: install every captured pin in one shot.
        if await installBatch(info.packages, pip: pip) {
            return .recreated
        }

        // A single unresolvable pin (e.g. a version yanked from PyPI since capture) fails
        // the whole batch install as one unit, even though the rest would resolve fine.
        // Retry package-by-package so everything that still resolves gets installed, and
        // only the genuinely broken pins are reported.
        var failed: [String] = []
        for package in info.packages where !(await installBatch([package], pip: pip)) {
            failed.append(package)
        }
        return failed.isEmpty ? .recreated : .partialInstall(failedPackages: failed)
    }

    private func installBatch(_ packages: [String], pip: URL) async -> Bool {
        let freezeFile = fileManager.temporaryDirectory
            .appendingPathComponent("moveapps-freeze-\(UUID().uuidString).txt")
        do {
            try packages.joined(separator: "\n").write(to: freezeFile, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? fileManager.removeItem(at: freezeFile) }

        let install = await runner.run(
            ["install", "-r", freezeFile.path],
            executable: pip.path,
            timeout: .seconds(300)
        )
        return install.didSucceed
    }
}
