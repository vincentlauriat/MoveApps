import Foundation

/// The strategy used to move a directory.
public enum MoveStrategy: Sendable, Hashable {
    /// Native atomic rename (`FileManager.moveItem`), used first.
    case rename
    /// Copy-then-delete fallback via `ditto`, used when the native rename fails
    /// (typically an iCloud FileProvider timeout).
    case dittoFallback
}

/// Progressive step emitted by `TransferPipeline.run` as an `AsyncStream`.
public enum TransferStep: Sendable {
    case detectingStack
    case materializingICloud(remaining: Int)
    case capturingVenvState(venv: URL)
    case snapshottingGitBefore
    case moving(strategy: MoveStrategy)
    case recreatingVenv(venv: URL)
    case reinstallingNodeModules
    case creatingCompatibilitySymlink
    case verifyingGitAfter
    case measuringSize
    case scanningResidualPaths
    case scanningSymlinks
    case finished(TransferResult)
}
