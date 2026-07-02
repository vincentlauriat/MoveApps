import Foundation

/// Detects the technology stack of a project directory.
/// Mirrors `detect_stack` in move-app.sh: `.git` at the root, and marker files found
/// with `find -maxdepth 2` (shallow, not a full recursive walk).
public struct StackDetector: Sendable {
    private var fileManager: FileManager { .default }

    public init() {}

    public func detect(at directory: URL) -> Set<StackTag> {
        var tags: Set<StackTag> = []

        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path, isDirectory: &isDir), isDir.boolValue {
            tags.insert(.git)
        }

        let names = shallowNames(at: directory, maxDepth: 2)
        if names.contains("package.json") { tags.insert(.node) }
        if names.contains(where: { $0 == "requirements.txt" || $0 == "pyproject.toml" || $0 == "Pipfile" }) {
            tags.insert(.python)
        }
        if names.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            tags.insert(.xcode)
        }
        if names.contains("Cargo.toml") { tags.insert(.rust) }
        if names.contains("go.mod") { tags.insert(.go) }

        return tags
    }

    /// Names of items at depth 1...maxDepth below `directory`, mirroring `find -maxdepth N`.
    private func shallowNames(at directory: URL, maxDepth: Int) -> Set<String> {
        var result: Set<String> = []
        func walk(_ url: URL, depth: Int) {
            guard depth <= maxDepth else { return }
            guard let items = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { return }
            for item in items {
                result.insert(item.lastPathComponent)
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory && depth < maxDepth {
                    walk(item, depth: depth + 1)
                }
            }
        }
        walk(directory, depth: 1)
        return result
    }
}
