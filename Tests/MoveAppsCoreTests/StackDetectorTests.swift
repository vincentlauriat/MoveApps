import Foundation
import Testing
@testable import MoveAppsCore

@Suite("StackDetector")
struct StackDetectorTests {
    @Test("detects markers within maxdepth 2 and ignores deeper ones")
    func detectsShallowMarkers() {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try? FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        Fixture.write("{}", to: root.appendingPathComponent("package.json"))          // depth 1 -> node
        Fixture.write("[build-system]", to: root.appendingPathComponent("pkg/pyproject.toml")) // depth 2 -> python
        Fixture.write("module x", to: root.appendingPathComponent("a/b/go.mod"))       // depth 3 -> NOT detected

        let tags = StackDetector().detect(at: root)
        #expect(tags.contains(.git))
        #expect(tags.contains(.node))
        #expect(tags.contains(.python))
        #expect(!tags.contains(.go))
        #expect(!tags.contains(.rust))
        #expect(!tags.contains(.xcode))
    }

    @Test("detects xcode project directory by suffix")
    func detectsXcode() {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )
        Fixture.write("[package]", to: root.appendingPathComponent("Cargo.toml"))

        let tags = StackDetector().detect(at: root)
        #expect(tags.contains(.xcode))
        #expect(tags.contains(.rust))
    }
}
