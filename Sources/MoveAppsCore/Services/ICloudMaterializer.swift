import Foundation

/// Where a materialization stage stands, reported on every polling attempt. Carries the starting
/// count and the time budget alongside what's left, because "348 restants" on its own says neither
/// how far along it is nor how long it may keep going.
public struct MaterializationProgress: Sendable, Hashable {
    /// Files still waiting to come down from iCloud.
    public let remaining: Int
    /// Files that were waiting when the stage started (`0` when there was nothing to download).
    public let total: Int
    /// Time spent polling so far.
    public let elapsed: Duration
    /// The most this stage will ever spend before giving up and letting the transfer proceed.
    public let limit: Duration
    /// `true` on the last report of the stage, whether everything came down or the budget ran out.
    public let isFinal: Bool

    public init(remaining: Int, total: Int, elapsed: Duration, limit: Duration, isFinal: Bool) {
        self.remaining = remaining
        self.total = total
        self.elapsed = elapsed
        self.limit = limit
        self.isFinal = isFinal
    }

    /// Files already downloaded since the stage started.
    public var downloaded: Int { max(0, total - remaining) }
}

/// Forces iCloud-dematerialized files to download before a move.
public protocol ICloudMaterializing: Sendable {
    /// Materializes pending stubs under `directory`, reporting progress on each polling attempt.
    /// Must be bounded: it always terminates even if items never materialize (the bash version
    /// caps at 30 attempts × 2s), and always ends on a report with `isFinal` set.
    func materialize(at directory: URL, onProgress: @Sendable (MaterializationProgress) -> Void) async
}

/// Real materializer using `FileManager.startDownloadingUbiquitousItem` plus bounded polling
/// on `ubiquitousItemDownloadingStatusKey` — no `brctl`, no `NSMetadataQuery`.
public actor FileProviderMaterializer: ICloudMaterializing {
    private let maxAttempts: Int
    private let pollInterval: Duration
    private var fileManager: FileManager { .default }

    public init(maxAttempts: Int = 30, pollInterval: Duration = .seconds(2)) {
        self.maxAttempts = maxAttempts
        self.pollInterval = pollInterval
    }

    public func materialize(at directory: URL, onProgress: @Sendable (MaterializationProgress) -> Void) async {
        let clock = ContinuousClock()
        let started = clock.now
        let limit = pollInterval * maxAttempts
        let total = pendingCount(under: directory)

        func report(remaining: Int, isFinal: Bool) {
            onProgress(MaterializationProgress(
                remaining: remaining,
                total: total,
                elapsed: started.duration(to: clock.now),
                limit: limit,
                isFinal: isFinal
            ))
        }

        guard total > 0 else {
            report(remaining: 0, isFinal: true)
            return
        }
        report(remaining: total, isFinal: false)

        for item in notDownloadedItems(under: directory) {
            try? fileManager.startDownloadingUbiquitousItem(at: item)
        }

        var attempt = 0
        while attempt < maxAttempts {
            try? await Task.sleep(for: pollInterval)
            let remaining = pendingCount(under: directory)
            attempt += 1
            // The budget running out is just as much an end of the stage as everything arriving:
            // either way this is the last thing said about it, so the line settles on a final state
            // instead of being left mid-count.
            report(remaining: remaining, isFinal: remaining == 0 || attempt == maxAttempts)
            if remaining == 0 { return }
        }
    }

    /// URLs of items under `directory` not yet materialized locally: `.icloud` stub files
    /// (dematerialized before any download starts, so they carry no downloading-status key of
    /// their own) plus any item whose `ubiquitousItemDownloadingStatusKey` reports
    /// `.notDownloaded` — the common case for dataless APFS placeholders under "Optimize Mac
    /// Storage", which do **not** carry the `.icloud` extension. Missing this second group used
    /// to mean `startDownloadingUbiquitousItem` was never called on them, so the stage spent its
    /// whole budget polling files it had never actually asked iCloud to fetch.
    private func notDownloadedItems(under directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "icloud" {
                result.append(url)
                continue
            }
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus, status == .notDownloaded {
                result.append(url)
            }
        }
        return result
    }

    private func pendingCount(under directory: URL) -> Int {
        notDownloadedItems(under: directory).count
    }
}
