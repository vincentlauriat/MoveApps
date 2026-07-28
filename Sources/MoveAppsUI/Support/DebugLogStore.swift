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
    public var timestamp: Date
    public var text: String
    public var kind: Kind

    /// Set on a line that reports the progress of one long-running stage. A new report with the
    /// same key overwrites this line in place rather than adding another one — the id survives, so
    /// the row updates instead of being torn down and rebuilt. `nil` for ordinary lines.
    ///
    /// Coalescing only ever applies to the line *immediately* at the bottom: any other line logged
    /// in between ends the group, and the next report starts a fresh line. That holds today because
    /// nothing else logs while a materialization stage polls — a future stage that logs
    /// concurrently would quietly get one line per report again.
    public let coalescingKey: String?

    public init(timestamp: Date, text: String, kind: Kind, coalescingKey: String? = nil) {
        self.timestamp = timestamp
        self.text = text
        self.kind = kind
        self.coalescingKey = coalescingKey
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

    /// Appends a line — or, when `coalescingKey` matches the line already at the bottom, rewrites
    /// that line in place. A stage that polls every couple of seconds (iCloud downloads, typically)
    /// therefore occupies one line that keeps counting up, instead of thirty near-identical ones.
    public func log(_ text: String, kind: DebugLogEntry.Kind = .info, coalescingKey: String? = nil) {
        let now = Date()

        if let coalescingKey, let last = entries.indices.last,
           entries[last].coalescingKey == coalescingKey {
            entries[last].timestamp = now
            entries[last].text = text
            entries[last].kind = kind
            // Routine progress updates stay out of the file, which can't rewrite a line and would
            // otherwise collect exactly the repetition being coalesced away here. Anything that
            // isn't routine — the stage settling on success, or on files that never arrived — is
            // worth a line of its own in the journal.
            if kind != .info {
                fileWriter?.enqueue(timestamp: now, kind: kind, text: text)
            }
            return
        }

        let entry = DebugLogEntry(timestamp: now, text: text, kind: kind, coalescingKey: coalescingKey)
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
