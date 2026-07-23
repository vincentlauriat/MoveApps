import Foundation

/// Discovers the individually-transferable projects directly under a root.
///
/// A top-level entry is surfaced as-is when it is itself a project (`StackDetector.isProjectRoot`
/// — has its own `.git` or a stack marker at its root). When it isn't, it's treated as a
/// container folder that merely groups several projects (e.g. a monorepo-style folder holding
/// multiple independent git repos as subdirectories) — its children are surfaced instead, so each
/// can be selected and transferred on its own. This applies even to a child that doesn't itself
/// look like a project by marker (no `.git`, no stack file) but still has content — it's still
/// listed (just with no stack tags), so it isn't silently dropped just because a sibling happens
/// to qualify as a project. A folder with no children at all (neither itself nor any child looks
/// like a project, and nothing else is in it) is still surfaced as a fallback, so nothing silently
/// disappears from the list — unless the folder is entirely empty, in which case there is nothing
/// to transfer and it's skipped outright.
public struct ProjectScanner: Sendable {
    private let detector: StackDetector
    private let checkoutStore: CheckoutReferenceStore
    private var fileManager: FileManager { .default }

    public init(
        detector: StackDetector = StackDetector(),
        checkoutStore: CheckoutReferenceStore = CheckoutReferenceStore()
    ) {
        self.detector = detector
        self.checkoutStore = checkoutStore
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

            // Checkout markers are checked first, before `isProjectRoot`/decomposition: a taken
            // slot must surface as a locked candidate, and — since an iCloud-evicted marker is
            // dot-prefixed — the `.skipsHiddenFiles` decomposition below would otherwise see the
            // slot as empty and drop it from the list entirely.
            if let checkout = checkoutStore.read(at: entry) {
                result.append(makeCheckoutCandidate(entry, container: nil, checkout: checkout))
                continue
            }

            // A shared resource folder (e.g. `Templates`) is one transferable unit: never
            // decomposed into its children, and transferred by copy (see `SharedResourceFolder`).
            if SharedResourceFolder.isSharedName(entry.lastPathComponent) {
                result.append(makeCandidate(entry))
                continue
            }

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

            let container = entry.lastPathComponent
            var containerCandidates: [ProjectCandidate] = []
            for child in allChildren where isDirectory(child) {
                if let checkout = checkoutStore.read(at: child) {
                    containerCandidates.append(makeCheckoutCandidate(child, container: container, checkout: checkout))
                } else if detector.isProjectRoot(at: child) {
                    containerCandidates.append(makeCandidate(child, container: container))
                } else if hasChildren(child) {
                    // Doesn't look like a project by marker (no `.git`, no stack file), but still
                    // has real content — surface it too rather than silently dropping it, the same
                    // way a fully marker-less container folder falls back to being listed as-is.
                    containerCandidates.append(makeCandidate(child, container: container))
                }
            }

            if containerCandidates.isEmpty {
                result.append(makeCandidate(entry))
            } else {
                result.append(contentsOf: containerCandidates)
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
            .filter {
                isDirectory($0)
                    && checkoutStore.read(at: $0) == nil
                    && !detector.isProjectRoot(at: $0)
                    && !SharedResourceFolder.isSharedName($0.lastPathComponent)
            }
            .map { $0.lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func hasChildren(_ url: URL) -> Bool {
        guard let children = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        return !children.isEmpty
    }

    private func makeCandidate(_ url: URL, container: String? = nil) -> ProjectCandidate {
        ProjectCandidate(
            name: url.lastPathComponent,
            path: url,
            stackTags: detector.detect(at: url),
            containerName: container
        )
    }

    private func makeCheckoutCandidate(_ url: URL, container: String?, checkout: CheckoutReference) -> ProjectCandidate {
        ProjectCandidate(
            name: url.lastPathComponent,
            path: url,
            stackTags: [],
            sizeBytes: checkout.sizeBytes,
            containerName: container,
            checkoutReference: checkout
        )
    }
}
