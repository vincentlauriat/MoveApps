import Foundation

/// Measures the on-disk size of a directory tree.
///
/// Uses `du -sk` rather than walking the tree with `FileManager`: `du` counts actual allocated
/// blocks (matching what Finder's "size on disk" reports), handles hard links correctly, and is
/// far faster on the large trees this app deals with (Vincent's roots hold ~90 projects / tens of
/// GB). Abstracted as an `actor` behind `ProcessRunner` for the same testability/timeout story as
/// `GitService`/`DittoCopier`.
public actor DiskUsage {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// The size of `directory` in bytes, or `nil` if it can't be measured (missing path, `du`
    /// failed, or timed out). `du -sk` reports 1024-byte blocks, so the value is multiplied back
    /// up to bytes.
    public func sizeBytes(of directory: URL) async -> Int64? {
        let result = await runner.run(
            ["-sk", directory.path],
            executable: "/usr/bin/du",
            timeout: .seconds(120)
        )
        // `du` exits non-zero whenever it hits an unreadable or locked subdirectory (e.g.
        // "Resource deadlock avoided" on some .dSYM/.framework bundles) — common on real project
        // trees — but it still prints a valid total to stdout. Only a timeout means no answer.
        guard !result.timedOut else { return nil }
        // `du -sk` output: "<kilobytes>\t<path>" — take the leading integer.
        let firstField = result.trimmedOutput.split(whereSeparator: { $0 == "\t" || $0 == " " }).first
        guard let kilobytes = firstField.flatMap({ Int64($0) }) else { return nil }
        return kilobytes * 1024
    }
}

/// Formats a byte count as a short human-readable string (e.g. `"1,3 Go"`), using the user's
/// locale. Kept as a plain helper so views can format sizes without importing the service.
public enum ByteFormat {
    public static func string(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
}
