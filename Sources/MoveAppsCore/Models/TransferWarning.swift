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
    /// The ditto fallback dropped working-tree files git cannot see as deletions (untracked or
    /// gitignored, e.g. a local `.env`). Caught by the mover's path-set comparison and escalated
    /// here — the same silent-loss class as `onyx`, but outside git's visibility. Drives
    /// `TransferResult.Status.critical` and preserves the source.
    case untrackedFileLostInCopy(paths: [String])
    /// Files under the destination still reference the old absolute source path.
    case residualPathReferences(files: [URL])
    /// A symlink under the destination points at a missing absolute target.
    case brokenSymlink(URL, target: String)
    /// A symlink under the destination points into a *different* project's tree.
    case crossProjectSymlink(URL, target: String, otherProject: String)
    /// The residual old-path scan could not enumerate the destination root (e.g. permission
    /// denied), so its "no references found" result is unreliable. Surfaced so an incomplete
    /// safety scan is never mistaken for a clean one.
    case residualScanIncomplete
    /// The symlink scan could not enumerate the destination root, so its "no problematic links"
    /// result is unreliable. Surfaced so an incomplete safety scan is never mistaken for a clean one.
    case symlinkScanIncomplete
    /// The Archive checkout marker couldn't be written back after an Archive → Active transfer,
    /// leaving the source slot without a "taken" trace. Not critical (the transfer itself
    /// succeeded), but surfaced so the hole is never silent.
    case checkoutReferenceWriteFailed(reason: String)

    /// Whether this warning must escalate the overall result to `.critical`.
    public var isCritical: Bool {
        switch self {
        case .gitDeletedFilesDetected, .untrackedFileLostInCopy: return true
        default: return false
        }
    }
}
