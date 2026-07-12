import Foundation
import MoveAppsCore

/// A detected project together with the root it currently lives under, so a transfer can be
/// aimed at the opposite root without re-deriving its location.
public struct QuickProject: Sendable, Identifiable, Hashable {
    public var candidate: ProjectCandidate
    public var root: RootKind
    public var id: URL { candidate.path }

    /// The root a transfer would move this project to.
    public var destination: RootKind { root == .active ? .archive : .active }
}

/// Stateless helpers shared by the main window and the menu-bar surfaces: scanning both roots
/// into `QuickProject`s (off the main actor) and turning a pipeline step into a French label.
/// Formerly the static side of `QuickPickViewModel`; extracted once the menu bar stopped running
/// transfers of its own, so nothing owns transfer state here anymore.
public enum ProjectListing {
    /// Scans both roots for projects, sorted by name. Safe to call off the main actor.
    public static func scanSync(_ locations: RootLocations) -> [QuickProject] {
        let scanner = ProjectScanner()
        var result: [QuickProject] = []

        for kind in RootKind.allCases {
            let root = locations.url(for: kind)
            let candidates = scanner.scan(root)
            result.append(contentsOf: candidates.map { QuickProject(candidate: $0, root: kind) })
        }

        return result.sorted {
            $0.candidate.name.localizedCaseInsensitiveCompare($1.candidate.name) == .orderedAscending
        }
    }

    /// A French description of a pipeline step, for the progress line.
    public static func describe(_ step: TransferStep) -> String {
        switch step {
        case .detectingStack: return "Détection de la stack…"
        case .materializingICloud(let remaining): return "Matérialisation iCloud (\(remaining) restants)…"
        case .capturingVenvState(let venv): return "Capture du venv \(venv.lastPathComponent)…"
        case .snapshottingGitBefore: return "Instantané git (avant)…"
        case .moving(let strategy):
            switch strategy {
            case .rename: return "Déplacement…"
            case .dittoFallback: return "Copie (ditto)…"
            }
        case .recreatingVenv(let venv): return "Recréation du venv \(venv.lastPathComponent)…"
        case .reinstallingNodeModules: return "Réinstallation de node_modules…"
        case .creatingCompatibilitySymlink: return "Création du lien de compatibilité…"
        case .verifyingGitAfter: return "Vérification git (après)…"
        case .measuringSize: return "Mesure de la taille…"
        case .scanningResidualPaths: return "Analyse des chemins résiduels…"
        case .scanningSymlinks: return "Analyse des liens symboliques…"
        case .finished(let result):
            switch result.status {
            case .ok: return "Terminé"
            case .warning: return "Terminé avec avertissements"
            case .critical: return "Critique — source préservée"
            case .failed: return "Échec : \(result.failureReason ?? "raison inconnue")"
            }
        }
    }
}
