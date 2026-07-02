import Foundation

/// One of the two roots a project can live under. Transfers are bidirectional between them.
public enum RootKind: String, Sendable, Codable, Hashable, CaseIterable {
    /// The active working root (`~/DevApps`).
    case active
    /// The archived / iCloud-backed root (`~/Documents/GitHub`).
    case archive
}
