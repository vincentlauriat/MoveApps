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

    @Test("surfaces a marker-less child alongside a real project instead of dropping it (Experimentations bug)")
    func surfacesMarkerLessSiblingInMixedContainer() {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        // A container ("Experimentations") holding one real project (has its own git repo)...
        try? fm.createDirectory(
            at: root.appendingPathComponent("Experimentations/ChromeUsage/.git"), withIntermediateDirectories: true
        )
        // ...and two siblings with real content but no `.git`/stack marker of their own — before
        // the fix, these were silently dropped entirely because a qualifying sibling existed.
        Fixture.write("notes", to: root.appendingPathComponent("Experimentations/ClaudeDeck/PRD.md"))
        Fixture.write("readme", to: root.appendingPathComponent("Experimentations/drawio-skill-1.34.0/README.md"))

        let candidates = ProjectScanner().scan(root)
        let names = Set(candidates.map(\.name))

        #expect(!names.contains("Experimentations"))
        #expect(names.contains("ChromeUsage"))
        #expect(names.contains("ClaudeDeck"))
        #expect(names.contains("drawio-skill-1.34.0"))
        #expect(candidates.count == 3)

        let claudeDeck = candidates.first { $0.name == "ClaudeDeck" }
        #expect(claudeDeck?.containerName == "Experimentations")
        #expect(claudeDeck?.stackTags.isEmpty == true)
    }

    @Test("surfaces checkout markers (top-level and nested) as locked candidates, not scanned projects")
    func surfacesCheckoutMarkers() throws {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CheckoutReferenceStore()
        // A taken project at the top level.
        let topSlot = root.appendingPathComponent("TakenTop", isDirectory: true)
        try store.write(at: topSlot, destinationPath: "/x/TakenTop", sizeBytes: 2048)

        // A taken project nested inside a container folder that also holds a real project.
        let nestedSlot = root.appendingPathComponent("Outils/TakenNested", isDirectory: true)
        try store.write(at: nestedSlot, destinationPath: nil, sizeBytes: nil)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Outils/RealOne/.git"), withIntermediateDirectories: true
        )

        let candidates = ProjectScanner().scan(root)

        let top = candidates.first { $0.name == "TakenTop" }
        #expect(top?.checkoutReference != nil)
        #expect(top?.checkoutReference?.sizeBytes == 2048)
        #expect(top?.sizeBytes == 2048)
        #expect(top?.stackTags.isEmpty == true)
        #expect(top?.containerName == nil)

        let nested = candidates.first { $0.name == "TakenNested" }
        #expect(nested?.checkoutReference != nil)
        #expect(nested?.containerName == "Outils")

        // The real sibling is still scanned normally, and the container is not surfaced itself.
        #expect(candidates.contains { $0.name == "RealOne" && $0.checkoutReference == nil })
        #expect(!candidates.contains { $0.name == "Outils" })
    }
}
