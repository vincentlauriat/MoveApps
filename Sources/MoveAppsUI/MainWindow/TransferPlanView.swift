import SwiftUI
import MoveAppsCore

/// Confirmation sheet for a pending transfer: shows the project and its direction, lets the user
/// choose the destination folder (root, an existing category folder, or a new one), toggle the
/// symlink-compatibility and node_modules-reinstall options, then confirm or cancel. Takes plain
/// closures rather than depending on a specific view model.
struct TransferPlanView: View {
    @Environment(\.dismiss) private var dismiss

    let plan: TransferPlan
    /// Existing category folders on the destination side, offered in the folder picker.
    let existingContainers: [String]
    let onCancel: () -> Void
    let onConfirm: (_ keepSymlink: Bool, _ reinstallNode: Bool, _ destinationContainer: String?) -> Void

    /// Where the project should land under the destination root.
    private enum Destination: Hashable {
        case root
        case existing(String)
        case new
    }

    @State private var destination: Destination = .root
    @State private var newContainer = ""
    @State private var keepSymlink = false
    @State private var reinstallNode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Confirmer le transfert")
                .font(.system(.title3, design: .rounded, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                Text(plan.project.name)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                HStack(spacing: 6) {
                    Text(sourceLabel)
                    Image(systemName: "arrow.right")
                    Text(destinationLabel)
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                StackTagRow(tags: sortedTags)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            destinationPicker

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
                    onConfirm(keepSymlink, reinstallNode, resolvedContainer)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear(perform: initializeDestination)
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dossier de destination")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Dossier de destination", selection: $destination) {
                Text("Racine").tag(Destination.root)
                if !existingContainers.isEmpty {
                    Divider()
                    ForEach(existingContainers, id: \.self) { name in
                        Text(name).tag(Destination.existing(name))
                    }
                }
                Divider()
                Text("Nouveau dossier…").tag(Destination.new)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if destination == .new {
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

    /// Seeds the picker from the plan's default container: root when nil, an existing entry when it
    /// matches one, otherwise "new folder" pre-filled with that name (e.g. the source's own folder
    /// that doesn't exist yet on the destination side).
    private func initializeDestination() {
        guard let container = plan.destinationContainer, !container.isEmpty else {
            destination = .root
            return
        }
        if existingContainers.contains(container) {
            destination = .existing(container)
        } else {
            destination = .new
            newContainer = container
        }
    }

    private var resolvedContainer: String? {
        switch destination {
        case .root: return nil
        case .existing(let name): return name
        case .new:
            let trimmed = newContainer.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private var sourceLabel: String {
        if let container = plan.project.containerName {
            return "\(rootLabel(plan.from)) ▸ \(container)"
        }
        return rootLabel(plan.from)
    }

    private var destinationLabel: String {
        if let container = resolvedContainer {
            return "\(rootLabel(plan.to)) ▸ \(container)"
        }
        return rootLabel(plan.to)
    }

    private var sortedTags: [StackTag] {
        plan.project.stackTags.sorted { $0.rawValue < $1.rawValue }
    }
}
