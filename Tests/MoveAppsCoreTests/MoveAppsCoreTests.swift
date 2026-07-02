import Foundation
import Testing
@testable import MoveAppsCore

@Suite("Scaffolding")
struct ScaffoldingTests {
    @Test("module loads")
    func moduleLoads() {
        #expect(Bundle(for: BundleAnchor.self).bundleIdentifier == "com.vincent.MoveAppsCoreTests")
    }
}

private final class BundleAnchor {}
