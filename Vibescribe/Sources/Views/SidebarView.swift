import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showDeleteConfirmation = false
    @State private var sessionToDelete: Session?

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedSessionId },
            set: { appState.selectedSessionId = $0 }
        )) {
            // Current Recording Section
            if let current = appState.currentSession {
                Section("Current") {
                    SessionRowView(session: current, isActive: true)
                        .tag(current.id)
                        .contextMenu {
                            Button {
                                exportSession(current)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                        }
                }
            }

            // Past Sessions Section
            if !appState.sessions.isEmpty {
                Section("Past Sessions") {
                    ForEach(appState.sessions) { session in
                        SessionRowView(session: session, isActive: false)
                            .tag(session.id)
                            .contextMenu {
                                Button {
                                    exportSession(session)
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }

                                Button(role: .destructive) {
                                    sessionToDelete = session
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }

            if appState.sessions.count < DatabaseManager.shared.getSessionCount() {
                Section {
                    Button("Load more") {
                        appState.loadMoreSessions()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .confirmationDialog(
            "Delete Session?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    appState.deleteSession(session)
                }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = appState.sessions[index]
            appState.deleteSession(session)
        }
    }

    private func exportSession(_ session: Session) {
        let panel = NSSavePanel()
        let baseName = session.name.isEmpty ? session.formattedDate : session.name
        let safeName = baseName.replacingOccurrences(of: ":", with: ".")
        panel.nameFieldStringValue = "\(safeName).txt"
        panel.allowedFileTypes = ["txt"]
        panel.canCreateDirectories = true

        panel.begin { [appState] response in
            guard response == .OK, let url = panel.url else { return }

            let text = session.lines
                .map { "\(appState.speakerDisplayLabel(for: $0.speaker)): \($0.text)" }
                .joined(separator: "\n")

            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                Task { @MainActor in
                    appState.showToast("Exported transcript")
                }
            }
        }
    }
}

struct SessionRowView: View {
    let session: Session
    let isActive: Bool
    @State private var isEditingName = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isEditingName {
                    TextField("Session name", text: Binding(
                        get: { session.name },
                        set: { session.name = $0 }
                    ))
                    .font(.headline)
                    .focused($isNameFocused)
                    .onSubmit { finishEditingName() }
                    .onAppear { isNameFocused = true }
                    .onChange(of: isNameFocused) { _, newValue in
                        if !newValue {
                            finishEditingName()
                        }
                    }
                } else {
                    if session.name.isEmpty {
                        TimelineView(.periodic(from: .now, by: 60)) { _ in
                            Text(session.relativeTimeString)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        .onTapGesture {
                            isEditingName = true
                        }
                    } else {
                        Text(session.name)
                            .font(.headline)
                            .lineLimit(1)
                            .onTapGesture {
                                isEditingName = true
                            }
                    }
                }

                Spacer()

                Text(session.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(session.preview.isEmpty ? "No transcript yet" : session.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !isActive && !session.name.isEmpty {
                Text(session.relativeTimeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func finishEditingName() {
        isEditingName = false
        DatabaseManager.shared.saveSession(session)
    }
}

#Preview {
    let appState = AppState()
    appState.sessions = [
        Session(name: "Test Session 1", startTime: Date().addingTimeInterval(-3600)),
        Session(name: "Test Session 2", startTime: Date().addingTimeInterval(-7200))
    ]

    return SidebarView()
        .environment(appState)
        .frame(width: 200, height: 400)
}
