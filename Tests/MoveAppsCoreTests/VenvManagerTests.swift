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

    // Found via a real round trip on a real project (LinkManager, Phase 5 cross-validation):
    // `pip freeze` pins exact versions, and a single pin that's since become unresolvable
    // (e.g. yanked from PyPI) failed the whole batched `pip install -r freeze.txt` as one
    // unit — losing every package, not just the broken one — and was misreported as
    // `.partialInstall(failedPackages: [])` with no indication of what actually failed.
    @Test("one unresolvable pin doesn't sink the whole install")
    func partialInstallFallsBackPerPackage() async throws {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let venv = root.appendingPathComponent("venv")
        let bogus = "totally-nonexistent-moveapps-test-package==999.999.999"
        let info = VenvInfo(path: venv, packages: ["certifi", bogus])

        let outcome = await VenvManager().recreate(info, at: venv)

        guard case .partialInstall(let failed) = outcome else {
            Issue.record("expected .partialInstall, got \(outcome)")
            return
        }
        #expect(failed == [bogus])

        // The resolvable package must still have been installed despite the bogus one.
        let pip = venv.appendingPathComponent("bin/pip").path
        #expect(FileManager.default.isExecutableFile(atPath: pip))
    }
}
