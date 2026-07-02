import Foundation

/// Copies a directory tree. Abstracted so tests can inject a fault-injecting copier.
public protocol DirectoryCopying: Sendable {
    /// Copies `source` to `destination`, returning whether the copy tool succeeded.
    /// Must not delete the source — deletion is the mover's responsibility after verification.
    func copy(from source: URL, to destination: URL) async -> Bool
}

/// Real copier using Apple's `ditto`, which handles iCloud materialization correctly.
public actor DittoCopier: DirectoryCopying {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func copy(from source: URL, to destination: URL) async -> Bool {
        let result = await runner.run(
            [source.path, destination.path],
            executable: "/usr/bin/ditto",
            timeout: .seconds(1800)
        )
        return result.didSucceed
    }
}
