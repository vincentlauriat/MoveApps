import Foundation
import Observation

/// One line in the debug log window: a timestamped, classified message.
public struct DebugLogEntry: Identifiable, Sendable {
    public enum Kind: Sendable {
        case info
        case warning
        case success
        case error
    }

    public let id = UUID()
    public let timestamp: Date
    public let text: String
    public let kind: Kind

    public init(timestamp: Date, text: String, kind: Kind) {
        self.timestamp = timestamp
        self.text = text
        self.kind = kind
    }
}

/// Captures every pipeline step and result emitted during transfers, feeding the on-demand debug
/// window. Always recording — it only re-logs the same `TransferStep`/`TransferWarning` text the
/// progress pill already renders, so the cost is negligible — meaning the window shows full
/// history the instant it's opened, even mid-transfer. Bounded to the most recent entries so a
/// long-running session never grows unbounded.
@MainActor
@Observable
public final class DebugLogStore {
    public private(set) var entries: [DebugLogEntry] = []

    private let maxEntries: Int

    public init(maxEntries: Int = 500) {
        self.maxEntries = maxEntries
    }

    public func log(_ text: String, kind: DebugLogEntry.Kind = .info) {
        entries.append(DebugLogEntry(timestamp: Date(), text: text, kind: kind))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func clear() {
        entries.removeAll()
    }
}
