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

    /// Optional on-disk mirror. Injected (rather than always-on) so tests keep an in-memory store;
    /// production wires a real writer so a journal survives relaunches.
    private let fileWriter: DebugLogFileWriter?

    public init(maxEntries: Int = 500, fileWriter: DebugLogFileWriter? = nil) {
        self.maxEntries = maxEntries
        self.fileWriter = fileWriter
    }

    public func log(_ text: String, kind: DebugLogEntry.Kind = .info) {
        let entry = DebugLogEntry(timestamp: Date(), text: text, kind: kind)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        fileWriter?.enqueue(timestamp: entry.timestamp, kind: kind, text: text)
    }

    /// The on-disk log file currently being written, when persistent logging is enabled — for the
    /// "Exporter" action to reveal in the Finder. `nil` when running in-memory only (e.g. tests).
    public func currentLogFileURL() -> URL? {
        fileWriter?.currentLogFileURL()
    }

    public func clear() {
        entries.removeAll()
    }
}
