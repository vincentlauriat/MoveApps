import Foundation

/// Outcome of a residual-path scan. `incomplete` distinguishes "the root couldn't be enumerated"
/// (permission denied, missing directory) from a genuinely clean tree — both would otherwise yield
/// an empty `matches` list and hide a failed safety scan.
public struct ResidualScanResult: Sendable {
    public let matches: [URL]
    public let incomplete: Bool

    public init(matches: [URL], incomplete: Bool) {
        self.matches = matches
        self.incomplete = incomplete
    }
}

/// Scans text files under a moved project for lingering references to the old absolute
/// source path (equivalent to `grep -rIl` with the same directory exclusions as the bash).
public struct ResidualPathScanner: Sendable {
    /// Directories skipped by both the residual scan and the symlink scan.
    static let excludedDirectoryNames: Set<String> = [
        ".git", "node_modules", ".build", "target", "DerivedData", ".venv", "venv"
    ]

    private let maxFileSizeBytes: Int
    private var fileManager: FileManager { .default }

    public init(maxFileSizeBytes: Int = 5_000_000) {
        self.maxFileSizeBytes = maxFileSizeBytes
    }

    public func scan(root: URL, forPath needle: String) -> ResidualScanResult {
        guard !needle.isEmpty else { return ResidualScanResult(matches: [], incomplete: false) }
        let needleData = Data(needle.utf8)
        var matches: [URL] = []
        // Set only when the *root* fails to enumerate: a failure deeper in the tree is expected to
        // be skipped silently, but a root that can't be read means the whole scan is unreliable.
        var rootUnreadable = false

        func walk(_ url: URL, isRoot: Bool) {
            guard let items = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            ) else {
                if isRoot { rootUnreadable = true }
                return
            }
            for item in items {
                if Self.excludedDirectoryNames.contains(item.lastPathComponent) { continue }
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                if values?.isSymbolicLink == true { continue }
                if values?.isDirectory == true {
                    walk(item, isRoot: false)
                    continue
                }
                if let size = values?.fileSize, size > maxFileSizeBytes { continue }
                guard let data = try? Data(contentsOf: item) else { continue }
                if isBinary(data) { continue }
                if data.range(of: needleData) != nil {
                    matches.append(item)
                }
            }
        }
        walk(root, isRoot: true)
        return ResidualScanResult(matches: matches, incomplete: rootUnreadable)
    }

    /// Treats a file as binary if a NUL byte appears in its leading bytes (like `grep -I`).
    private func isBinary(_ data: Data) -> Bool {
        data.prefix(8000).contains(0)
    }
}
