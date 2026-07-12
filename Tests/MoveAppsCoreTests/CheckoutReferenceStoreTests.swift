import Foundation
import Testing
@testable import MoveAppsCore

@Suite("CheckoutReferenceStore")
struct CheckoutReferenceStoreTests {
    @Test("write → read → clear round trip")
    func roundTrip() throws {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let slot = root.appendingPathComponent("MyProject", isDirectory: true)

        let store = CheckoutReferenceStore()
        try store.write(at: slot, destinationPath: "/Users/x/DevApps/MyProject", sizeBytes: 4096)

        let read = store.read(at: slot)
        #expect(read != nil)
        // The host is recovered from the (sanitized) filename, so it round-trips as the sanitized
        // form of this Mac's host name — deterministic even when the JSON body isn't materialized.
        #expect(read?.hostName == CheckoutReferenceStore.sanitize(CheckoutReferenceStore.currentHostName()))
        #expect(read?.hostName.isEmpty == false)
        #expect(read?.destinationPath == "/Users/x/DevApps/MyProject")
        #expect(read?.sizeBytes == 4096)
        // Filename-derived day agrees with the JSON-encoded takenAt (both normalized to the day).
        #expect(Calendar.current.isDate(read!.takenAt, inSameDayAs: Date()))

        store.clear(at: slot)
        #expect(!FileManager.default.fileExists(atPath: slot.path))
        #expect(store.read(at: slot) == nil)
    }

    @Test("reads an iCloud-evicted placeholder: host + day from the filename, bonus fields nil")
    func readsEvictedPlaceholder() {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let slot = root.appendingPathComponent("EvictedProject", isDirectory: true)
        try? FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)

        // A real dot-prefixed `.icloud` placeholder whose body is *not* materialized JSON.
        let placeholder = slot.appendingPathComponent(".MOVEAPPS-CHECKOUT__MacBook-Pro__2026-07-12.json.icloud")
        FileManager.default.createFile(atPath: placeholder.path, contents: Data())

        let store = CheckoutReferenceStore()
        let read = store.read(at: slot)
        #expect(read != nil)
        #expect(read?.hostName == "MacBook-Pro")
        #expect(read?.destinationPath == nil)
        #expect(read?.sizeBytes == nil)

        let day = Calendar.current.dateComponents([.year, .month, .day], from: read!.takenAt)
        #expect(day.year == 2026)
        #expect(day.month == 7)
        #expect(day.day == 12)
    }

    @Test("clearOrphans finds and clears a marker filed under a different container")
    func clearOrphansAcrossContainer() throws {
        let archive = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: archive) }

        let store = CheckoutReferenceStore()
        // Orphan stub at archive/Outils/Widget (a container folder), plus an unrelated real folder.
        let orphanSlot = archive.appendingPathComponent("Outils/Widget", isDirectory: true)
        try store.write(at: orphanSlot, destinationPath: nil, sizeBytes: nil)
        try FileManager.default.createDirectory(
            at: archive.appendingPathComponent("Outils/Unrelated"), withIntermediateDirectories: true
        )

        store.clearOrphans(named: "Widget", under: archive)

        #expect(!FileManager.default.fileExists(atPath: orphanSlot.path))
        #expect(FileManager.default.fileExists(atPath: archive.appendingPathComponent("Outils/Unrelated").path))
    }
}
