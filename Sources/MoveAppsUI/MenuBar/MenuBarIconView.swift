import SwiftUI

/// Static menu-bar glyph for MoveApps. Unlike WifiManager there is no continuous multi-state
/// status to indicate, so this is a plain SF Symbol that switches to a transfer glyph while a
/// transfer is running.
public struct MenuBarIconView: View {
    let isBusy: Bool

    public init(isBusy: Bool) {
        self.isBusy = isBusy
    }

    public var body: some View {
        Image(systemName: isBusy ? "arrow.triangle.2.circlepath" : "arrow.left.arrow.right.circle")
            .accessibilityLabel(isBusy ? "Transfert en cours" : "MoveApps")
    }
}
