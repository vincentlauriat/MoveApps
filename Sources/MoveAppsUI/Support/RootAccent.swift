import SwiftUI
import AppKit
import MoveAppsCore

/// A distinct colour per root — a muted teal for Actif, a muted amber for Archive — so a glance at
/// an icon, a stat chip or a transfer arrow tells you which direction it belongs to without
/// reading text. Both are bespoke dynamic colours (adapt between light and dark like a native
/// system colour) rather than the system `.accentColor` / `.orange`, whose saturated,
/// off-the-shelf tones read as a loud "candy" accent instead of the muted, considered pair the
/// rest of the window is styled around.
func rootAccent(_ kind: RootKind) -> Color {
    switch kind {
    case .active: return Color(nsColor: .activeTeal)
    case .archive: return Color(nsColor: .archiveAmber)
    }
}

private extension NSColor {
    static let activeTeal = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.247, green: 0.792, blue: 0.839, alpha: 1)  // #3FCAD6
            : NSColor(red: 0.055, green: 0.486, blue: 0.525, alpha: 1)  // #0E7C86
    }

    static let archiveAmber = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.886, green: 0.635, blue: 0.357, alpha: 1)  // #E2A25B
            : NSColor(red: 0.659, green: 0.388, blue: 0.106, alpha: 1)  // #A8631B
    }
}
