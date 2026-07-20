import Foundation
import Testing
@testable import MoveAppsCore

@Suite("RootPathsSettings")
struct RootPathsSettingsTests {
    @Test("rootsCollide is true for the same folder")
    func sameFolder() {
        let url = URL(fileURLWithPath: "/Users/x/DevApps", isDirectory: true)
        #expect(RootPathsSettings.rootsCollide(url, url))
    }

    @Test("rootsCollide ignores trailing-slash and dot-segment variants of the same path")
    func normalizedVariants() {
        let a = URL(fileURLWithPath: "/Users/x/DevApps", isDirectory: true)
        let b = URL(fileURLWithPath: "/Users/x/Archive/../DevApps", isDirectory: true)
        #expect(RootPathsSettings.rootsCollide(a, b))
    }

    @Test("rootsCollide is false for distinct folders")
    func distinctFolders() {
        let active = URL(fileURLWithPath: "/Users/x/DevApps", isDirectory: true)
        let archive = URL(fileURLWithPath: "/Users/x/Documents/GitHub", isDirectory: true)
        #expect(!RootPathsSettings.rootsCollide(active, archive))
    }

    @Test("rootsCollide is false when one path is nested inside the other")
    func nestedIsNotCollision() {
        let parent = URL(fileURLWithPath: "/Users/x/DevApps", isDirectory: true)
        let child = URL(fileURLWithPath: "/Users/x/DevApps/Sub", isDirectory: true)
        #expect(!RootPathsSettings.rootsCollide(parent, child))
    }
}
