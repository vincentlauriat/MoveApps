import Foundation

/// Mirrors every debug entry to a rolling on-disk log under `~/Library/Logs/MoveApps/`, so a
/// journal survives app relaunches — the in-memory `DebugLogStore` is cleared on quit. One file
/// per day keeps rotation trivial and dependency-free.
///
/// Lines are handed off through an `AsyncStream` and drained by a single background consumer, so
/// `enqueue` never blocks the caller (the main actor, on every logged line) yet the file stays in
/// the exact order the lines were logged even when a transfer emits a burst within one tick.
public final class DebugLogFileWriter: Sendable {
    private struct Line: Sendable {
        let timestamp: Date
        let text: String
    }

    private let directory: URL
    private let continuation: AsyncStream<Line>.Continuation

    public init(directory: URL = DebugLogFileWriter.defaultDirectory()) {
        self.directory = directory
        let (stream, continuation) = AsyncStream<Line>.makeStream()
        self.continuation = continuation
        Task.detached(priority: .utility) {
            await DebugLogFileWriter.drain(stream, into: directory)
        }
    }

    /// `~/Library/Logs/MoveApps`.
    public static func defaultDirectory() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("MoveApps", isDirectory: true)
    }

    /// Queues one line for the background writer. Cheap and non-blocking.
    public func enqueue(timestamp: Date, kind: DebugLogEntry.Kind, text: String) {
        continuation.yield(Line(timestamp: timestamp, text: Self.format(kind: kind, text: text)))
    }

    /// The log file being written today; ensures the directory exists so the "Exporter" action can
    /// reveal it (or its folder) in the Finder even before the first line is written.
    public func currentLogFileURL() -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self.fileURL(in: directory, for: Date())
    }

    private static func drain(_ stream: AsyncStream<Line>, into directory: URL) async {
        let fileManager = FileManager.default
        for await line in stream {
            let url = fileURL(in: directory, for: line.timestamp)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let data = "\(stamp(line.timestamp)) \(line.text)\n".data(using: .utf8) else { continue }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func format(kind: DebugLogEntry.Kind, text: String) -> String {
        let tag: String
        switch kind {
        case .info: tag = "INFO"
        case .warning: tag = "WARN"
        case .success: tag = "OK"
        case .error: tag = "ERROR"
        }
        return "[\(tag)] \(text)"
    }

    /// A fixed, sortable, locale-independent local-time stamp: `2026-07-19 14:23:45.123`.
    private static func stamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date
        )
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d.%03d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0, (c.nanosecond ?? 0) / 1_000_000
        )
    }

    private static func fileURL(in directory: URL, for date: Date) -> URL {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let name = String(format: "MoveApps-%04d-%02d-%02d.log", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return directory.appendingPathComponent(name, isDirectory: false)
    }
}
