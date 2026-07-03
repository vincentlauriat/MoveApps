import SwiftUI
import MoveAppsCore

/// Window for creating a new project from a template. Pick a template, name it, optionally seed a
/// git repo; the project is created under the Active root. Shows a clear result (or a hint to
/// configure a templates folder when none are found).
///
/// This is a standalone `Window` scene, not a sheet inside the menu-bar popover: the popover is
/// ephemeral and closes the instant it loses key focus, so opening the template `Picker`'s native
/// menu from within it would dismiss the whole thing. A real window is decoupled from that.
public struct NewProjectView: View {
    @Environment(DashboardViewModel.self) private var model
    @Environment(RootPathsController.self) private var rootPaths
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedTemplate: ProjectTemplate?
    @State private var gitInit = true

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Nouveau projet")
                .font(.system(.title3, design: .rounded, weight: .bold))

            if model.templates.isEmpty {
                emptyTemplatesHint
            } else {
                form
            }

            if let result = model.lastCreation {
                resultBanner(result)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Fermer", role: .cancel) {
                    model.clearCreationResult()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)

                Spacer()

                Button("Créer") {
                    if let template = selectedTemplate {
                        model.createProject(named: name, from: template, gitInit: gitInit)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(!canCreate)
            }
        }
        .padding(22)
        .frame(width: 440, height: 380)
        .onAppear {
            // Pick up any templates added since the popover last scanned, then default-select one.
            model.reloadTemplates()
            if selectedTemplate == nil { selectedTemplate = model.templates.first }
        }
    }

    private var canCreate: Bool {
        selectedTemplate != nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isCreating
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Modèle").font(.caption).foregroundStyle(.secondary)
                Picker("Modèle", selection: $selectedTemplate) {
                    ForEach(model.templates) { template in
                        Text(template.name).tag(Optional(template))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Nom du projet").font(.caption).foregroundStyle(.secondary)
                TextField("MonNouveauProjet", text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Toggle("Initialiser un dépôt git", isOn: $gitInit)
                .toggleStyle(.switch)

            Text("Créé sous \(rootPaths.displayPath(for: .active))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyTemplatesHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Aucun modèle trouvé", systemImage: "questionmark.folder")
                .font(.system(.body, design: .rounded, weight: .semibold))
            Text("Placez un sous-dossier par modèle dans le dossier de modèles, puis configurez-le dans les Réglages.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(rootPaths.displayTemplatesPath)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func resultBanner(_ result: ProjectCreationResult) -> some View {
        let (icon, color, text): (String, Color, String) = {
            switch result {
            case .created(let url, let gitInitialized):
                return ("checkmark.circle.fill", .green,
                        "Projet créé : \(url.lastPathComponent)\(gitInitialized ? " (git initialisé)" : "")")
            case .destinationExists(let url):
                return ("exclamationmark.triangle.fill", .orange,
                        "Un élément nommé « \(url.lastPathComponent) » existe déjà.")
            case .copyFailed:
                return ("xmark.octagon.fill", .red, "Échec de la copie du modèle.")
            case .invalidName:
                return ("exclamationmark.triangle.fill", .orange, "Nom de projet invalide.")
            }
        }()

        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(color.opacity(0.12)),
                         in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
