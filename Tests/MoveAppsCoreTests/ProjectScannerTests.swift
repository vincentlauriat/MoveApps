import Foundation
import Testing
@testable import MoveAppsCore

@Suite("ProjectScanner")
struct ProjectScannerTests {
    @Test("surfaces a project directly and unpacks a container folder into its sub-projects")
    func unpacksContainerFolders() {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        // A real top-level project (its own git repo) — surfaced as-is.
        try? fm.createDirectory(at: root.appendingPathComponent("LinkManager/.git"), withIntermediateDirectories: true)

        // A container folder (like "Gatsby") that is NOT itself a project, but groups three
        // independent sub-projects, each with its own git repo.
        try? fm.createDirectory(at: root.appendingPathComponent("Gatsby/GatsbyExecution/.git"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: root.appendingPathComponent("Gatsby/GatbyViewer/.git"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: root.appendingPathComponent("Gatsby/MomentumBot/.git"), withIntermediateDirectories: true)

        // A stray folder that is neither a project itself nor contains any project-looking
        // children — still surfaced as a fallback so nothing silently disappears.
        Fixture.write("hello", to: root.appendingPathComponent("Miscellaneous/notes.txt"))

        let candidates = ProjectScanner().scan(root)
        let names = Set(candidates.map(\.name))

        #expect(names.contains("LinkManager"))
        #expect(!names.contains("Gatsby"))
        #expect(names.contains("GatsbyExecution"))
        #expect(names.contains("GatbyViewer"))
        #expect(names.contains("MomentumBot"))
        #expect(names.contains("Miscellaneous"))
        #expect(candidates.count == 5)

        let gatsbyExecution = candidates.first { $0.name == "GatsbyExecution" }
        #expect(
            gatsbyExecution?.path.resolvingSymlinksInPath()
                == root.appendingPathComponent("Gatsby/GatsbyExecution").resolvingSymlinksInPath()
        )
        #expect(gatsbyExecution?.stackTags.contains(.git) == true)

        // Sub-projects unpacked from a container folder record that container's name, so the
        // UI can show where they live; top-level projects and the fallback-listed stray folder
        // carry no container name.
        #expect(gatsbyExecution?.containerName == "Gatsby")
        let linkManager = candidates.first { $0.name == "LinkManager" }
        #expect(linkManager?.containerName == nil)
        let miscellaneous = candidates.first { $0.name == "Miscellaneous" }
        #expect(miscellaneous?.containerName == nil)
    }
}
