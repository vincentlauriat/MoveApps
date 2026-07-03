import SwiftUI
import MoveAppsCore

/// Confirmation sheet for a batch transfer: lists the selected projects and their direction, lets
/// the user keep each project's own folder (default) or send them all into one destination folder,
/// toggle the shared options, then confirm or cancel. View-model-agnostic via closures.
struct BatchTransferView: View {
    @Environment(\.dismiss) private var dismiss

    let batch: PendingBatch
    /// Existing category folders on the destination side, offered when forcing one folder.
    let existingContainers: [String]
    let onCancel: () -> Void
    let onConfirm: (_ keepSymlink: Bool, _ reinstallNode: Bool, _ folderMode: BatchFolderMode) -> Void

    /// Where the batch files each project.
    private enum FolderChoice: Hashable {
        case preserveEach
        case root
        case existing(String)
        case new
    }

    @State private var choice: FolderChoice = .preserveEach
    @State private var newContainer = ""
    @State private var keepSymlink = false
    @State private var reinstallNode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Transférer \(batch.projects.count) projet\(batch.projects.count == 1 ? "" : "s")")
                .font(.system(.title3, design: .rounded, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(rootLabel(batch.from))
                    Image(systemName: "arrow.right")
                    Text(rootLabel(batch.to))
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(batch.projects) { project in
                            HStack(spacing: 6) {
                                Image(systemName: "circle.fill").font(.system(size: 4))
                                    .foregroundStyle(.tertiary)
                                Text(project.candidate.name)
                                    .font(.system(.callout, design: .rounded, weight: .medium))
                                if let container = project.candidate.containerName {
                                    Text("· \(container)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            folderPicker

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Conserver un lien de compatibilité", isOn: $keepSymlink)
                Toggle("Réinstaller node_modules", isOn: $reinstallNode)
            }
            .toggleStyle(.switch)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 0)

            HStack {
                Button("Annuler", role: .cancel) {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)

                Spacer()

                Button("Confirmer") {
                    onConfirm(keepSymlink, reinstallNode, resolvedMode)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dossier de destination")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Dossier de destination", selection: $choice) {
                Text("Conserver le dossier d'origine").tag(FolderChoice.preserveEach)
                Divider()
                Text("Racine").tag(FolderChoice.root)
                if !existingContainers.isEmpty {
                    ForEach(existingContainers, id: \.self) { name in
                        Text(name).tag(FolderChoice.existing(name))
                    }
                }
                Text("Nouveau dossier…").tag(FolderChoice.new)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if choice == .new {
                TextField("Nom du dossier", text: $newContainer)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var resolvedMode: BatchFolderMode {
        switch choice {
        case .preserveEach: return .preserveEach
        case .root: return .fixed(nil)
        case .existing(let name): return .fixed(name)
        case .new:
            let trimmed = newContainer.trimmingCharacters(in: .whitespacesAndNewlines)
            return .fixed(trimmed.isEmpty ? nil : trimmed)
        }
    }
}
