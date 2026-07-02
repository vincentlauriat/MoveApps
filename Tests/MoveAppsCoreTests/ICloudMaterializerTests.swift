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
        await materializer.materialize(at: root) { remaining in log.record(remaining) }

        // Initial report + one per attempt; never hangs, and the stub is still pending.
        #expect(log.values.count == 4)
        #expect(log.values.last ?? 0 > 0)
    }

    @Test("fake never-resolving materializer stays bounded", .timeLimit(.minutes(1)))
    func fakeMaterializerIsBounded() async {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ProgressLog()
        let materializer = NeverResolvingMaterializer(attempts: 5)
        await materializer.materialize(at: root) { remaining in log.record(remaining) }
        #expect(log.values.count == 5)
    }
}
