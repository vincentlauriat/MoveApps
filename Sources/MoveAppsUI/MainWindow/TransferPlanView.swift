import SwiftUI
import MoveAppsCore

/// Confirmation sheet for a pending transfer: shows the project and its direction, lets the
/// user toggle the symlink-compatibility and node_modules-reinstall options, then confirms or
/// cancels.
struct TransferPlanView: View {
    @Environment(MainWindowViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let plan: TransferPlan

    @State private var keepSymlink = false
    @State private var reinstallNode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirmer le transfert")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(plan.project.name)
                    .font(.title3).bold()
                HStack(spacing: 6) {
                    Text(rootLabel(plan.from))
                    Image(systemName: "arrow.right")
                    Text(rootLabel(plan.to))
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if !sortedTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(sortedTags, id: \.self) { tag in
                            Text(tag.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Conserver un lien de compatibilité", isOn: $keepSymlink)
                Toggle("Réinstaller node_modules", isOn: $reinstallNode)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Annuler", role: .cancel) {
                    model.cancelPending()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Confirmer") {
                    model.confirmPending(keepSymlink: keepSymlink, reinstallNode: reinstallNode)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var sortedTags: [StackTag] {
        plan.project.stackTags.sorted { $0.rawValue < $1.rawValue }
    }
}
