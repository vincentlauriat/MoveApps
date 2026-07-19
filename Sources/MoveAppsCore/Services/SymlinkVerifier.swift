import Foundation

/// Scans a moved project for problematic symlinks:
///  - broken links (absolute target missing) within the project, and
///  - cross-project links pointing into a *different* project's tree.
///
/// Build/derived directories are excluded entirely: a self-referential broken symlink
/// inside `build/` or `DerivedData/` is benign and must not be flagged as a critical
/// cross-project link.
public struct SymlinkVerifier: Sendable {
    /// Directories skipped entirely: version control, dependency, and build-output trees.
    /// Build outputs (`build`, `.build`, `DerivedData`, `target`) hold self-referential /
    /// absolute symlinks that are benign artifacts and must not surface as findings.
    static let excludedDirectoryNames: Set<String> = [
        ".git", "node_modules", ".venv", "venv",
        "build", ".build", "DerivedData", "target",
    ]

    private var fileManager: FileManager { .default }

    public init() {}

    public func scan(root: URL) -> [TransferWarning] {
        var warnings: [TransferWarning] = []
        let rootPath = standardized(root).path
        let appsRoot = standardized(root.deletingLastPathComponent()).path

        var rootUnreadable = false
        let links = symlinks(under: root, rootUnreadable: &rootUnreadable)
        // A root that can't be enumerated makes "no problematic links" unreliable — surface it
        // rather than returning an empty (falsely clean) result.
        if rootUnreadable {
            warnings.append(.symlinkScanIncomplete)
        }

        for link in links {
            guard let target = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else { continue }
            let resolved = resolvedTarget(target, linkParent: link.deletingLastPathComponent())
            let resolvedPath = resolved.path

            let isInsideRoot = resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/")
            if isInsideRoot {
                // Internal link: flag only if it points at a missing target.
                if !fileManager.fileExists(atPath: resolvedPath) {
                    warnings.append(.brokenSymlink(link, target: target))
                }
            } else {
                // Points outside this project: cross-project reference.
                let other = otherProjectName(resolvedPath: resolvedPath, appsRoot: appsRoot)
                warnings.append(.crossProjectSymlink(link, target: target, otherProject: other))
            }
        }
        return warnings
    }

    private func symlinks(under root: URL, rootUnreadable: inout Bool) -> [URL] {
        var result: [URL] = []
        func walk(_ url: URL, isRoot: Bool) {
            guard let items = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
                options: []
            ) else {
                if isRoot { rootUnreadable = true }
                return
            }
            for item in items {
                if Self.excludedDirectoryNames.contains(item.lastPathComponent) {
                    continue
                }
                let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if values?.isSymbolicLink == true {
                    result.append(item)
                } else if values?.isDirectory == true {
                    walk(item, isRoot: false)
                }
            }
        }
        walk(root, isRoot: true)
        return result
    }

    private func resolvedTarget(_ target: String, linkParent: URL) -> URL {
        if target.hasPrefix("/") {
            return standardized(URL(fileURLWithPath: target))
        }
        return standardized(linkParent.appendingPathComponent(target))
    }

    private func standardized(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path).standardizedFileURL
    }

    private func otherProjectName(resolvedPath: String, appsRoot: String) -> String {
        if resolvedPath.hasPrefix(appsRoot + "/") {
            let rest = String(resolvedPath.dropFirst(appsRoot.count + 1))
            if let first = rest.split(separator: "/").first {
                return String(first)
            }
        }
        return URL(fileURLWithPath: resolvedPath).lastPathComponent
    }
}
