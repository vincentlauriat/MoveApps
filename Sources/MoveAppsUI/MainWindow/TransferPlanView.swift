import SwiftUI
import MoveAppsCore

/// Confirmation sheet for a pending transfer: shows the project and its direction, lets the
/// user toggle the symlink-compatibility and node_modules-reinstall options, then confirms or
/// cancels. Takes plain closures rather than depending on a specific view model, so it can be
/// reused unmodified from both the main window (`MainWindowViewModel`) and the menu bar popup
/// (`QuickPickViewModel`) — those two view models are deliberately independent state, not shared.
struct TransferPlanView: View {
    @Environment(\.dismiss) private var dismiss

    let plan: TransferPlan
    let onCancel: () -> Void
    let onConfirm: (_ keepSymlink: Bool, _ reinstallNode: Bool) -> Void

    @State private var keepSymlink = false
    @State private var reinstallNode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Confirmer le transfert")
                .font(.system(.title3, design: .rounded, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                Text(plan.project.name)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                if let container = plan.project.containerName {
                    Label(container, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(rootLabel(plan.from))
                    Image(systemName: "arrow.right")
                    Text(rootLabel(plan.to))
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                StackTagRow(tags: sortedTags)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                    onConfirm(keepSymlink, reinstallNode)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var sortedTags: [StackTag] {
        plan.project.stackTags.sorted { $0.rawValue < $1.rawValue }
    }
}
