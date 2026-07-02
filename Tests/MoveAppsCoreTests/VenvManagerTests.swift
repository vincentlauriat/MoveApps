import Foundation
import Testing
@testable import MoveAppsCore

@Suite("VenvManager")
struct VenvManagerTests {
    @Test("detects venvs by pyvenv.cfg, not by folder name")
    func detectsByPyvenvCfg() {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        // Real venv: has pyvenv.cfg.
        let realVenv = root.appendingPathComponent(".venv")
        Fixture.write("home = /usr/bin\nversion = 3.12\n", to: realVenv.appendingPathComponent("pyvenv.cfg"))

        // Decoy: a directory literally named "venv" WITHOUT a pyvenv.cfg.
        let decoy = root.appendingPathComponent("venv")
        Fixture.write("not a venv", to: decoy.appendingPathComponent("readme.txt"))

        let found = VenvManager().findVenvs(in: root)
        #expect(found.map { $0.standardizedFileURL.path } == [realVenv.standardizedFileURL.path])
    }

    @Test("capture returns empty package list when no pip is present")
    func captureWithoutPip() async {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        Fixture.write("version = 3.12\n", to: root.appendingPathComponent("pyvenv.cfg"))

        let info = await VenvManager().capture(root)
        #expect(info.packages.isEmpty)
        #expect(info.path == root)
    }
}
