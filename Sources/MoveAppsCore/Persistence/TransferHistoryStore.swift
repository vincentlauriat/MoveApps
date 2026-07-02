import Foundation

/// Persists transfer history as JSON at an injected file URL (not a hard-coded Application
/// Support path, so it is testable). Writes are atomic (temp file + replace).
public actor TransferHistoryStore {
    private let fileURL: URL
    private var fileManager: FileManager { .default }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func all() -> [TransferRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TransferRecord].self, from: data)) ?? []
    }

    public func append(_ record: TransferRecord) throws {
        var records = all()
        records.append(record)
        try save(records)
    }

    private func save(_ records: [TransferRecord]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        // `.atomic` writes to a temp file then renames into place.
        try data.write(to: fileURL, options: .atomic)
    }
}
