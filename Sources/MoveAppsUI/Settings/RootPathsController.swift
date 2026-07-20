import AppKit
import Observation
import MoveAppsCore

/// AppKit-facing wrapper around `RootPathsSettings` (which is deliberately AppKit-free in Core).
///
/// Owns the `NSOpenPanel` directory picking and the persistence of the user's choice as a
/// bookmark in `UserDefaults`, resolving it again at the next launch. The app is **not**
/// sandboxed (it spawns `git`/`ditto` subprocesses, which the sandbox forbids), so a true
/// security-scoped bookmark can only be *created* when the sandbox entitlements are present.
/// We therefore try `.withSecurityScope` first and fall back to a plain bookmark, and on
/// resolution do the same — this keeps the intended behaviour without breaking the
/// non-sandboxed build.
@MainActor
@Observable
public final class RootPathsController {
    public let settings: RootPathsSettings

    /// Roots whose bookmark failed to resolve (stale or revoked). The UI shows a
    /// "to reconfigure" hint and falls back to the default path rather than crashing.
    public private(set) var rootsNeedingReconfiguration: Set<RootKind> = []

    /// The last rejected directory pick, surfaced next to the matching "Choisir…" button. Set when
    /// a chosen folder collides with the other root (source == destination would be nonsensical),
    /// cleared on the next successful pick.
    public private(set) var lastPickError: RootPickError?

    /// A rejected pick tied to the root whose button it should appear beside.
    public struct RootPickError: Equatable {
        public let kind: RootKind
        public let message: String
    }

    /// The templates folder isn't a `RootKind` (not a transfer endpoint), so it gets its own
    /// bookmark slot alongside the two roots.
    private let templatesKey = "rootBookmark.templates"

    public init() {
        self.settings = RootPathsSettings()
        for kind in RootKind.allCases {
            resolveStoredBookmark(for: kind)
        }
        resolveStoredTemplatesBookmark()
    }

    // MARK: - Display

    public func displayPath(for kind: RootKind) -> String {
        abbreviate(settings.url(for: kind))
    }

    public var displayTemplatesPath: String {
        abbreviate(settings.templatesURL)
    }

    public func needsReconfiguration(_ kind: RootKind) -> Bool {
        rootsNeedingReconfiguration.contains(kind)
    }

    private func abbreviate(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Picking

    /// Presents an `NSOpenPanel` to choose a directory for the given root and persists it.
    public func chooseDirectory(for kind: RootKind) {
        guard let url = pickDirectory(startingAt: settings.url(for: kind)) else { return }
        let other: RootKind = kind == .active ? .archive : .active
        guard !RootPathsSettings.rootsCollide(url, settings.url(for: other)) else {
            lastPickError = RootPickError(
                kind: kind,
                message: "Identique à l'autre racine — choisissez un dossier différent."
            )
            return
        }
        lastPickError = nil
        apply(url: url, for: kind)
        storeBookmark(for: url, key: defaultsKey(for: kind))
        rootsNeedingReconfiguration.remove(kind)
    }

    /// Presents an `NSOpenPanel` to choose the templates folder and persists it.
    public func chooseTemplatesDirectory() {
        guard let url = pickDirectory(startingAt: settings.templatesURL) else { return }
        settings.templatesURL = url
        storeBookmark(for: url, key: templatesKey)
    }

    private func pickDirectory(startingAt start: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.directoryURL = start
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - Persistence

    private func defaultsKey(for kind: RootKind) -> String { "rootBookmark.\(kind.rawValue)" }

    private func apply(url: URL, for kind: RootKind) {
        switch kind {
        case .active: settings.activeURL = url
        case .archive: settings.archiveURL = url
        }
    }

    private func storeBookmark(for url: URL, key: String) {
        guard let data = makeBookmark(for: url) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func resolveStoredBookmark(for kind: RootKind) {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(for: kind)) else {
            return // never configured — keep the default from RootPathsSettings.
        }
        guard let (url, isStale) = resolveBookmark(data) else {
            rootsNeedingReconfiguration.insert(kind)
            return
        }
        // Keep the resource accessible for the app's lifetime; a non-sandboxed app never
        // needs to balance this, and there is no teardown point on a long-lived controller.
        _ = url.startAccessingSecurityScopedResource()
        apply(url: url, for: kind)
        if isStale {
            // Re-encode so the next launch resolves cleanly; if it fails, flag for reconfig.
            if let refreshed = makeBookmark(for: url) {
                UserDefaults.standard.set(refreshed, forKey: defaultsKey(for: kind))
            } else {
                rootsNeedingReconfiguration.insert(kind)
            }
        }
    }

    private func resolveStoredTemplatesBookmark() {
        guard let data = UserDefaults.standard.data(forKey: templatesKey),
              let (url, isStale) = resolveBookmark(data) else {
            return // never configured or unresolvable — keep the default.
        }
        _ = url.startAccessingSecurityScopedResource()
        settings.templatesURL = url
        if isStale, let refreshed = makeBookmark(for: url) {
            UserDefaults.standard.set(refreshed, forKey: templatesKey)
        }
    }

    private func makeBookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return (url, isStale)
        }
        isStale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return (url, isStale)
        }
        return nil
    }
}
