import Foundation

/// A non-fatal (or, for `gitDeletedFilesDetected`, safety-critical) condition surfaced
/// during a transfer. Named cases only — never free-form strings — so the UI can render
/// each condition specifically and callers can react programmatically.
public enum TransferWarning: Sendable, Hashable, Codable {
    /// A Python venv was recreated but no captured package list was available.
    case venvRecreatedEmpty(venv: URL)
    /// Some packages failed to reinstall into a recreated venv.
    case venvPartialInstall(venv: URL, failedPackages: [String])
    /// The optional node_modules reinstall failed.
    case nodeReinstallFailed(reason: String)
    /// The git dirty-file count differed before/after the move (benign: no deletions).
    case gitDirtyCountChanged(before: Int, after: Int)
    /// Git reports tracked files deleted after the move that were not deleted before.
    /// This is the `onyx` production bug signal and drives `TransferResult.Status.critical`.
    case gitDeletedFilesDetected(paths: [String])
    /// Files under the destination still reference the old absolute source path.
    case residualPathReferences(files: [URL])
    /// A symlink under the destination points at a missing absolute target.
    case brokenSymlink(URL, target: String)
    /// A symlink under the destination points into a *different* project's tree.
    case crossProjectSymlink(URL, target: String, otherProject: String)
    /// The Archive checkout marker couldn't be written back after an Archive → Active transfer,
    /// leaving the source slot without a "taken" trace. Not critical (the transfer itself
    /// succeeded), but surfaced so the hole is never silent.
    case checkoutReferenceWriteFailed(reason: String)

    /// Whether this warning must escalate the overall result to `.critical`.
    public var isCritical: Bool {
        if case .gitDeletedFilesDetected = self { return true }
        return false
    }
}
