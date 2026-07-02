import Foundation

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

    public func scan(root: URL, forPath needle: String) -> [URL] {
        guard !needle.isEmpty else { return [] }
        let needleData = Data(needle.utf8)
        var matches: [URL] = []

        func walk(_ url: URL) {
            guard let items = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            ) else { return }
            for item in items {
                if Self.excludedDirectoryNames.contains(item.lastPathComponent) { continue }
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                if values?.isSymbolicLink == true { continue }
                if values?.isDirectory == true {
                    walk(item)
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
        walk(root)
        return matches
    }

    /// Treats a file as binary if a NUL byte appears in its leading bytes (like `grep -I`).
    private func isBinary(_ data: Data) -> Bool {
        data.prefix(8000).contains(0)
    }
}
