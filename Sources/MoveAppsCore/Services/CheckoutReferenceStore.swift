import Foundation

/// Writes, reads and clears the checkout marker that turns an Archive slot into a "taken by X on
/// day Y" reference instead of a full project.
///
/// The essential facts (host, day) live in the **filename** — `MOVEAPPS-CHECKOUT__<host>__<date>.json`
/// — not only in the JSON body, because the Archive is iCloud-backed: a hidden marker's *content*
/// can be evicted to a `.name.icloud` placeholder whose body reads as nothing. Names survive
/// eviction (dot-prefixed), so a directory listing that does **not** skip hidden files still finds
/// the placeholder and the regex still recovers host+day from it. The JSON body only adds the
/// optional `destinationPath`/`sizeBytes`, degrading to `nil` when not yet materialized.
public struct CheckoutReferenceStore: Sendable {
    private var fileManager: FileManager { .default }

    public init() {}

    // MARK: - Host / filename

    /// This Mac's human-readable name (System Settings > Sharing > "MonMac"), the same string
    /// `Host.current().localizedName` and `scutil --get ComputerName` return. `ProcessInfo.hostName`
    /// is deliberately not used as the primary source: on a network where reverse-DNS resolves the
    /// local address to an ISP-assigned name, it returns that instead of anything Mac-identifying
    /// (e.g. `2a01cb040d5e5c003c50608d0543a509.ipv6.abo.wanadoo.fr`), which would defeat the whole
    /// point of the marker. Kept only as a fallback, with a trailing `.local` stripped.
    public static func currentHostName() -> String {
        if let localized = Host.current().localizedName, !localized.isEmpty {
            return localized
        }
        let raw = ProcessInfo.processInfo.hostName
        if raw.hasSuffix(".local") { return String(raw.dropLast(".local".count)) }
        return raw
    }

    /// Every character outside `[A-Za-z0-9-]` becomes `-`, so the host round-trips through the
    /// filename regex unambiguously.
    static func sanitize(_ host: String) -> String {
        String(host.map { ch in
            (ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-")) ? ch : "-"
        })
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func markerName(host: String, date: Date) -> String {
        "MOVEAPPS-CHECKOUT__\(sanitize(host))__\(dayFormatter.string(from: date)).json"
    }

    /// Matches both the plain marker and its iCloud-evicted placeholder (`.name.json.icloud`).
    private static let markerPattern = try! NSRegularExpression(
        pattern: #"^\.?MOVEAPPS-CHECKOUT__([A-Za-z0-9-]+)__(\d{4}-\d{2}-\d{2})\.json(\.icloud)?$"#
    )

    /// Returns the host and day strings captured from a marker filename, or `nil` if it doesn't match.
    static func match(_ filename: String) -> (host: String, day: String)? {
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let m = markerPattern.firstMatch(in: filename, range: range),
              let hostRange = Range(m.range(at: 1), in: filename),
              let dayRange = Range(m.range(at: 2), in: filename)
        else { return nil }
        return (String(filename[hostRange]), String(filename[dayRange]))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Write

    /// Creates the marker inside `directory`, recreating the directory first (after a move the
    /// original slot no longer exists — a rename took it, or step 7 deleted the copied source).
    /// `takenAt` is normalized to the day so it agrees with the day recovered from the filename.
    public func write(at directory: URL, destinationPath: String?, sizeBytes: Int64?) throws {
        let host = Self.currentHostName()
        let now = Date()
        let day = Self.dayFormatter.date(from: Self.dayFormatter.string(from: now)) ?? now
        let reference = CheckoutReference(
            hostName: host,
            takenAt: day,
            destinationPath: destinationPath,
            sizeBytes: sizeBytes
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.markerName(host: host, date: now), isDirectory: false)
        try Self.encoder.encode(reference).write(to: url, options: .atomic)
    }

    // MARK: - Read

    /// The checkout reference held in `directory`, or `nil` when the directory holds no marker.
    /// Lists without `.skipsHiddenFiles` so an evicted dot-prefixed placeholder is still seen.
    public func read(at directory: URL) -> CheckoutReference? {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return nil }

        for entry in entries {
            guard let matched = Self.match(entry.lastPathComponent),
                  let day = Self.dayFormatter.date(from: matched.day)
            else { continue }

            var destinationPath: String?
            var sizeBytes: Int64?
            if let data = try? Data(contentsOf: entry),
               let decoded = try? Self.decoder.decode(CheckoutReference.self, from: data) {
                destinationPath = decoded.destinationPath
                sizeBytes = decoded.sizeBytes
            }
            return CheckoutReference(
                hostName: matched.host,
                takenAt: day,
                destinationPath: destinationPath,
                sizeBytes: sizeBytes
            )
        }
        return nil
    }

    // MARK: - Clear

    /// Removes the whole slot (marker + its now-empty directory), so the Archive position becomes
    /// cleanly absent until the project is checked back in.
    public func clear(at directory: URL) {
        try? fileManager.removeItem(at: directory)
    }

    /// Sweeps the archive root (top level + one level into container folders, mirroring
    /// `ProjectScanner`'s shallow structure) for a directory named `projectName` that holds a
    /// checkout marker, and clears it — for the check-in case where a project returns under a
    /// different container than the one it was taken from.
    public func clearOrphans(named projectName: String, under root: URL) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }

        for entry in entries {
            guard isDirectory(entry) else { continue }
            if entry.lastPathComponent == projectName, read(at: entry) != nil {
                clear(at: entry)
                continue
            }
            guard let children = try? fileManager.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { continue }
            for child in children where isDirectory(child) {
                if child.lastPathComponent == projectName, read(at: child) != nil {
                    clear(at: child)
                }
            }
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
