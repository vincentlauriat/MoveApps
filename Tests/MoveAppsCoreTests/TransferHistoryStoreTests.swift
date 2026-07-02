import Foundation
import Testing
@testable import MoveAppsCore

@Suite("TransferHistoryStore")
struct TransferHistoryStoreTests {
    @Test("append then reload round-trips records including warnings")
    func roundTrip() async throws {
        let dir = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("history/records.json")

        let store = TransferHistoryStore(fileURL: fileURL)
        #expect(await store.all().isEmpty)

        let record = TransferRecord(
            projectName: "onyx",
            from: .archive,
            to: .active,
            sourcePath: URL(fileURLWithPath: "/old/onyx"),
            destinationPath: URL(fileURLWithPath: "/new/onyx"),
            status: .critical,
            warnings: [.gitDeletedFilesDetected(paths: ["src/lost.swift"])]
        )
        try await store.append(record)

        // A fresh store instance reads what was persisted.
        let reloaded = TransferHistoryStore(fileURL: fileURL)
        let all = await reloaded.all()
        #expect(all.count == 1)
        #expect(all.first?.projectName == "onyx")
        #expect(all.first?.status == .critical)
        #expect(all.first?.warnings == [.gitDeletedFilesDetected(paths: ["src/lost.swift"])])
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
