import Foundation

/// An in-memory cache of per-project on-disk sizes, shared between the main window (which warms it
/// in the background after each scan) and `IndexGenerator` (which reads it to render a size column
/// without any `du` on the hot path). Deliberately **not** persisted to disk — sizes are cheap to
/// rebuild each session and would go stale between launches. Keys are standardized so a value
/// stored from one scan is found by a lookup from another (differently-normalized) scan.
public actor ProjectSizeCache {
    private var sizes: [URL: Int64] = [:]

    public init() {}

    public func size(for url: URL) -> Int64? {
        sizes[url.standardizedFileURL]
    }

    public func store(_ bytes: Int64, for url: URL) {
        sizes[url.standardizedFileURL] = bytes
    }

    /// A snapshot of the whole cache, for handing to `IndexGenerator.write`.
    public func snapshot() -> [URL: Int64] {
        sizes
    }
}
