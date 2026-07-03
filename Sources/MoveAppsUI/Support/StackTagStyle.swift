import SwiftUI
import MoveAppsCore

/// Presentation-only mapping from a detected stack technology to an icon and accent tint, used
/// to render the small technology badges throughout the UI. Purely cosmetic — carries no logic
/// and has no bearing on detection itself (see `MoveAppsCore/StackDetector`).
extension StackTag {
    var icon: String {
        switch self {
        case .git: return "arrow.triangle.branch"
        case .node: return "shippingbox.fill"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .xcode: return "hammer.fill"
        case .rust: return "gearshape.2.fill"
        case .go: return "bolt.fill"
        }
    }

    var tint: Color {
        switch self {
        case .git: return .orange
        case .node: return .green
        case .python: return .blue
        case .xcode: return .indigo
        case .rust: return .brown
        case .go: return .cyan
        }
    }
}

/// A small glass badge for one detected stack technology: icon + label, tinted to the
/// technology's accent colour, rendered as its own Liquid Glass capsule. Used in every project
/// row and the transfer confirmation sheet so the tag treatment stays consistent everywhere.
struct StackTagView: View {
    let tag: StackTag

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: tag.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(tag.rawValue)
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundStyle(tag.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glassEffect(.regular.tint(tag.tint.opacity(0.35)), in: Capsule())
    }
}

/// A row of a project's stack tags, sorted for stable ordering, sharing one glass group so
/// adjacent badges read as a cohesive cluster rather than separate floating pills.
struct StackTagRow: View {
    let tags: [StackTag]

    var body: some View {
        if !tags.isEmpty {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        StackTagView(tag: tag)
                    }
                }
            }
        }
    }
}
