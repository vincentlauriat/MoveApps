import Foundation

/// The strategy used to move a directory.
public enum MoveStrategy: Sendable, Hashable {
    /// Native atomic rename (`FileManager.moveItem`), used first.
    case rename
    /// Copy-then-delete fallback via `ditto`, used when the native rename fails
    /// (typically an iCloud FileProvider timeout).
    case dittoFallback
    /// Pure copy for a shared resource folder — the source is intentionally left in place.
    case copy
}

/// Which side of the move a git integrity check looked at.
public enum GitCheckPhase: Sendable, Hashable {
    case beforeMove
    case afterMove
}

/// Progressive step emitted by `TransferPipeline.run` as an `AsyncStream`.
public enum TransferStep: Sendable {
    case detectingStack
    case materializingICloud(MaterializationProgress)
    case capturingVenvState(venv: URL)
    case snapshottingGitBefore
    case moving(strategy: MoveStrategy)
    case recreatingVenv(venv: URL)
    case reinstallingNodeModules
    case creatingCompatibilitySymlink
    case verifyingGitAfter
    /// The outcome of a git integrity check, so the log line for the step says how it went
    /// instead of only announcing it.
    case gitIntegrityChecked(GitCheckPhase, repo: String, GitIntegrity)
    case measuringSize
    case scanningResidualPaths
    case scanningSymlinks
    case finished(TransferResult)
}
