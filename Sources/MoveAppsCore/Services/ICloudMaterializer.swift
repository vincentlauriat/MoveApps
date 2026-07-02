import Foundation

/// Forces iCloud-dematerialized files to download before a move.
public protocol ICloudMaterializing: Sendable {
    /// Materializes pending stubs under `directory`, reporting the remaining stub count on
    /// each polling attempt. Must be bounded: it always terminates even if items never
    /// materialize (the bash version caps at 30 attempts × 2s).
    func materialize(at directory: URL, onProgress: @Sendable (Int) -> Void) async
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

    public func materialize(at directory: URL, onProgress: @Sendable (Int) -> Void) async {
        var remaining = pendingCount(under: directory)
        onProgress(remaining)
        guard remaining > 0 else { return }

        for stub in stubs(under: directory) {
            try? fileManager.startDownloadingUbiquitousItem(at: stub)
        }

        var attempt = 0
        while attempt < maxAttempts {
            try? await Task.sleep(for: pollInterval)
            remaining = pendingCount(under: directory)
            onProgress(remaining)
            if remaining == 0 { return }
            attempt += 1
        }
    }

    /// URLs of `.icloud` stub files under `directory`.
    private func stubs(under directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "icloud" {
            result.append(url)
        }
        return result
    }

    private func pendingCount(under directory: URL) -> Int {
        var count = stubs(under: directory).count
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey]
        ) else { return count }
        for case let url as URL in enumerator {
            guard let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus else { continue }
            if status == .notDownloaded {
                count += 1
            }
        }
        return count
    }
}
