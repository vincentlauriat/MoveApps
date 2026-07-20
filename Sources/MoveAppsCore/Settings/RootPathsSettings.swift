import Foundation
import Observation

/// Sendable snapshot of the two root locations, consumed by the pipeline actor.
public struct RootLocations: Sendable, Hashable {
    public var active: URL
    public var archive: URL

    public init(active: URL, archive: URL) {
        self.active = active
        self.archive = archive
    }

    public func url(for kind: RootKind) -> URL {
        switch kind {
        case .active: return active
        case .archive: return archive
        }
    }

    public static let `default` = RootLocations(
        active: RootPathsSettings.defaultURL(for: .active),
        archive: RootPathsSettings.defaultURL(for: .archive)
    )
}

/// Observable model of the configured root paths.
///
/// Phase 1 keeps this to the data model only. Security-scoped bookmarks and `NSOpenPanel`
/// (which touch AppKit) are deliberately out of scope here and belong to the app target in
/// a later phase — the `activeURL`/`archiveURL` vars are the extension point for overrides.
@Observable
public final class RootPathsSettings {
    public var activeURL: URL
    public var archiveURL: URL
    /// Folder holding project templates (one subfolder per template). Not a transfer endpoint —
    /// deliberately kept out of `RootKind` so it never leaks into the bidirectional transfer
    /// logic — only a source for "new project from template". Defaults to `~/DevApps/.templates`.
    public var templatesURL: URL

    public init(
        activeURL: URL = RootPathsSettings.defaultURL(for: .active),
        archiveURL: URL = RootPathsSettings.defaultURL(for: .archive),
        templatesURL: URL = RootPathsSettings.defaultTemplatesURL()
    ) {
        self.activeURL = activeURL
        self.archiveURL = archiveURL
        self.templatesURL = templatesURL
    }

    public static func defaultTemplatesURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("DevApps/.templates", isDirectory: true)
    }

    public func url(for kind: RootKind) -> URL {
        switch kind {
        case .active: return activeURL
        case .archive: return archiveURL
        }
    }

    /// A Sendable snapshot for handing to the pipeline actor.
    public var locations: RootLocations {
        RootLocations(active: activeURL, archive: archiveURL)
    }

    public static func defaultURL(for kind: RootKind) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch kind {
        case .active: return home.appendingPathComponent("DevApps", isDirectory: true)
        case .archive: return home.appendingPathComponent("Documents/GitHub", isDirectory: true)
        }
    }

    /// Whether two roots point at the same folder — a configuration that would make a transfer
    /// nonsensical (source == destination). Compares standardized file URLs so trailing-slash and
    /// `.`/`..` variants of the same path are treated as identical.
    public static func rootsCollide(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL == b.standardizedFileURL
    }
}
