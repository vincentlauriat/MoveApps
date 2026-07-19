import SwiftUI
import AppKit
import MoveAppsCore

/// A standalone, on-demand window tracing every pipeline step of every transfer as it runs — for
/// when a move is taking a while and the compact progress pill isn't enough detail. Opened from
/// the main window's toolbar; purely observational, it never affects the transfer itself.
public struct DebugLogView: View {
    @Environment(DebugLogStore.self) private var log

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if log.entries.isEmpty {
                emptyState
            } else {
                logList
            }
        }
        .frame(minWidth: 460, minHeight: 320)
    }

    private var header: some View {
        HStack {
            Text("Debug")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Spacer()
            Button("Exporter le journal") { revealLogFile() }
                .buttonStyle(.glass)
            Button("Effacer") { log.clear() }
                .buttonStyle(.glass)
                .disabled(log.entries.isEmpty)
        }
        .padding(16)
    }

    /// Reveals today's persistent log file in the Finder — or its folder, when today's file doesn't
    /// exist yet — so an incident journal can be grabbed even after the app was relaunched.
    private func revealLogFile() {
        guard let url = log.currentLogFileURL() else { return }
        let directory = url.deletingLastPathComponent()
        if !NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: directory.path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
        }
    }

    private var emptyState: some View {
        Text("Aucune activité pour l'instant — le journal se remplit dès qu'un transfert démarre.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(log.entries) { entry in
                        DebugLogRowView(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .onChange(of: log.entries.count) {
                guard let last = log.entries.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

/// One log line: timestamp, a status glyph, then the message — coloured by `entry.kind` so
/// warnings and failures jump out of a long-running trace without having to read every line.
private struct DebugLogRowView: View {
    let entry: DebugLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 12)
            Text(entry.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
    }

    private var icon: String {
        switch entry.kind {
        case .info: return "circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .info: return .primary
        case .warning: return .orange
        case .success: return .green
        case .error: return .red
        }
    }
}
