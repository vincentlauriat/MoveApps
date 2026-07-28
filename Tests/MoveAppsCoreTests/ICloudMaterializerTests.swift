import Foundation
import Testing
@testable import MoveAppsCore

@Suite("iCloud materialization is bounded")
struct ICloudMaterializerTests {
    @Test("real materializer terminates after max attempts when stubs never resolve", .timeLimit(.minutes(1)))
    func realMaterializerIsBounded() async {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        // A `.icloud` stub that will never materialize (not actually ubiquitous).
        Fixture.write("stub", to: root.appendingPathComponent("document.pdf.icloud"))

        let log = ProgressLog()
        let materializer = FileProviderMaterializer(maxAttempts: 3, pollInterval: .milliseconds(5))
        await materializer.materialize(at: root) { progress in log.record(progress) }

        // Initial report + one per attempt; never hangs, and the stub is still pending.
        #expect(log.values.count == 4)
        #expect(log.values.last ?? 0 > 0)
    }

    @Test("every report carries the starting total, and only the last one is final")
    func reportsCarryTotalAndEndOnFinal() async {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        Fixture.write("stub", to: root.appendingPathComponent("document.pdf.icloud"))

        let log = ProgressLog()
        let materializer = FileProviderMaterializer(maxAttempts: 2, pollInterval: .milliseconds(5))
        await materializer.materialize(at: root) { progress in log.record(progress) }

        let reports = log.reports
        #expect(reports.allSatisfy { $0.total == 1 })
        #expect(reports.allSatisfy { $0.limit == .milliseconds(10) })
        // A stage that gave up still ends on a final report, so a live progress line settles
        // instead of being left mid-count.
        #expect(reports.last?.isFinal == true)
        #expect(reports.dropLast().allSatisfy { !$0.isFinal })
        #expect(reports.last?.remaining == 1)
        #expect(reports.last?.downloaded == 0)
    }

    @Test("a directory with nothing to download reports once, final and empty")
    func nothingToDownloadReportsOnce() async {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        Fixture.write("local", to: root.appendingPathComponent("README.md"))

        let log = ProgressLog()
        let materializer = FileProviderMaterializer(maxAttempts: 3, pollInterval: .milliseconds(5))
        await materializer.materialize(at: root) { progress in log.record(progress) }

        #expect(log.reports.count == 1)
        #expect(log.reports.first?.total == 0)
        #expect(log.reports.first?.isFinal == true)
    }

    @Test("fake never-resolving materializer stays bounded", .timeLimit(.minutes(1)))
    func fakeMaterializerIsBounded() async {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ProgressLog()
        let materializer = NeverResolvingMaterializer(attempts: 5)
        await materializer.materialize(at: root) { progress in log.record(progress) }
        #expect(log.values.count == 5)
    }
}
