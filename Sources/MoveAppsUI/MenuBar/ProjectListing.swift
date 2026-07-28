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

    /// Roots whose contents can't be listed because access was denied, distinct from an empty or
    /// absent root. An empty directory lists as `[]` without throwing; a permission refusal throws
    /// on a path that still exists — so a throw against a directory that *does* exist is the tell,
    /// which avoids guessing the exact error code TCC surfaces (it varies: Cocoa vs. POSIX `EPERM`).
    public static func deniedRoots(_ locations: RootLocations) -> Set<RootKind> {
        let fileManager = FileManager.default
        var denied: Set<RootKind> = []
        for kind in RootKind.allCases {
            let root = locations.url(for: kind)
            do {
                _ = try fileManager.contentsOfDirectory(atPath: root.path)
            } catch {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    denied.insert(kind)
                }
            }
        }
        return denied
    }

    /// A French description of a pipeline step, for the progress line.
    public static func describe(_ step: TransferStep) -> String {
        switch step {
        case .detectingStack: return "Détection de la stack…"
        case .materializingICloud(let progress): return describe(progress)
        case .capturingVenvState(let venv): return "Capture du venv \(venv.lastPathComponent)…"
        case .snapshottingGitBefore: return "Instantané git (avant)…"
        case .moving(let strategy):
            switch strategy {
            case .rename: return "Déplacement…"
            case .dittoFallback: return "Copie (ditto)…"
            case .copy: return "Copie (source conservée)…"
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

    /// The iCloud download stage in words. Says how many of how many have come down, how long it's
    /// been going and how long it may still go — a bare "N restants", repeated every two seconds
    /// with the same N, tells you neither whether it's progressing nor when it will stop.
    public static func describe(_ progress: MaterializationProgress) -> String {
        let elapsed = seconds(progress.elapsed)
        guard progress.total > 0 else {
            return "iCloud : aucun fichier à télécharger"
        }
        guard progress.isFinal else {
            return "Téléchargement iCloud : \(progress.downloaded)/\(progress.total) fichiers récupérés — "
                + "\(elapsed) s (\(seconds(progress.limit)) s max)"
        }
        if progress.remaining == 0 {
            return "Téléchargement iCloud terminé : \(progress.total) fichiers récupérés en \(elapsed) s"
        }
        // Deliberately says only what is known — how many didn't arrive in the time allowed. Why
        // they didn't (offline, paused, a slow large file) isn't something the pending count can
        // tell us, and guessing here would send anyone reading the log after the wrong thing.
        return "Téléchargement iCloud incomplet : \(progress.remaining) fichiers sur \(progress.total) "
            + "non récupérés après \(elapsed) s — le transfert continue"
    }

    /// How a materialization report should be coloured in the debug log: a stage that ends with
    /// files still missing is worth noticing, everything else is routine.
    public static func kind(_ progress: MaterializationProgress) -> DebugLogEntry.Kind {
        guard progress.isFinal else { return .info }
        if progress.total == 0 { return .info }
        return progress.remaining == 0 ? .success : .warning
    }

    private static func seconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds)
    }

    /// A French description of a transfer warning, shared by the history view and the debug log.
    public static func describe(_ warning: TransferWarning) -> String {
        switch warning {
        case .venvRecreatedEmpty(let venv):
            return "Venv recréé sans liste de paquets : \(venv.lastPathComponent)"
        case .venvPartialInstall(let venv, let failed):
            return "Venv \(venv.lastPathComponent) : \(failed.count) paquet(s) non réinstallé(s)"
        case .nodeReinstallFailed(let reason):
            return "Échec réinstallation node_modules : \(reason)"
        case .gitDirtyCountChanged(let before, let after):
            return "Nombre de fichiers modifiés git différent (\(before) → \(after))"
        case .gitDeletedFilesDetected(let paths):
            return "Fichiers suivis supprimés détectés : \(paths.count)"
        case .untrackedFileLostInCopy(let paths):
            return "Fichiers non suivis perdus à la copie : \(paths.count)"
        case .residualPathReferences(let files):
            return "Références au chemin source résiduelles : \(files.count) fichier(s)"
        case .brokenSymlink(let url, let target):
            return "Lien cassé : \(url.lastPathComponent) → \(target)"
        case .crossProjectSymlink(let url, _, let other):
            return "Lien vers un autre projet : \(url.lastPathComponent) → \(other)"
        case .checkoutReferenceWriteFailed(let reason):
            return "Échec d'écriture de la trace de prise : \(reason)"
        case .residualScanIncomplete:
            return "Analyse des références résiduelles incomplète (dossier illisible)"
        case .symlinkScanIncomplete:
            return "Analyse des liens symboliques incomplète (dossier illisible)"
        }
    }
}
