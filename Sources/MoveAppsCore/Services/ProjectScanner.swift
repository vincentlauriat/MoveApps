import Foundation

/// Discovers the individually-transferable projects directly under a root.
///
/// A top-level entry is surfaced as-is when it is itself a project (`StackDetector.isProjectRoot`
/// — has its own `.git` or a stack marker at its root). When it isn't, it's treated as a
/// container folder that merely groups several projects (e.g. a monorepo-style folder holding
/// multiple independent git repos as subdirectories) — its qualifying children are surfaced
/// instead, so each can be selected and transferred on its own. A folder with no qualifying
/// children (neither itself nor any child looks like a project) is still surfaced as a fallback,
/// so nothing silently disappears from the list — unless the folder is entirely empty, in which
/// case there is nothing to transfer and it's skipped outright.
public struct ProjectScanner: Sendable {
    private let detector: StackDetector
    private var fileManager: FileManager { .default }

    public init(detector: StackDetector = StackDetector()) {
        self.detector = detector
    }

    public func scan(_ root: URL) -> [ProjectCandidate] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [ProjectCandidate] = []
        for entry in entries {
            guard isDirectory(entry) else { continue }

            if detector.isProjectRoot(at: entry) {
                result.append(makeCandidate(entry))
                continue
            }

            let allChildren = (try? fileManager.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            guard !allChildren.isEmpty else { continue }  // nothing in it to transfer

            let children = allChildren.filter { isDirectory($0) && detector.isProjectRoot(at: $0) }

            if children.isEmpty {
                result.append(makeCandidate(entry))
            } else {
                let container = entry.lastPathComponent
                result.append(contentsOf: children.map { makeCandidate($0, container: container) })
            }
        }
        return result
    }

    /// Names of the top-level folders under `root` that are *not* themselves projects — i.e. the
    /// category/container folders a project can be filed under (`Outils`, `NetworkTools`, …).
    /// Sorted, so the transfer sheet can offer them as destination folders.
    public func containerFolders(in root: URL) -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { isDirectory($0) && !detector.isProjectRoot(at: $0) }
            .map { $0.lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func makeCandidate(_ url: URL, container: String? = nil) -> ProjectCandidate {
        ProjectCandidate(
            name: url.lastPathComponent,
            path: url,
            stackTags: detector.detect(at: url),
            containerName: container
        )
    }
}
