import Foundation

/// A technology detected inside a project directory (mirrors `detect_stack` in move-app.sh).
public enum StackTag: String, Sendable, Codable, Hashable, CaseIterable {
    case git
    case node
    case python
    case xcode
    case rust
    case go
}
