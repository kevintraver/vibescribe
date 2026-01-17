import SwiftUI

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
                }
            }

            // Past Sessions Section
            if !appState.sessions.isEmpty {
                Section("Past Sessions") {
                    ForEach(appState.sessions) { session in
                        SessionRowView(session: session, isActive: false)
                            .tag(session.id)
                            .contextMenu {
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
}

struct SessionRowView: View {
    let session: Session
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(session.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(session.preview.isEmpty ? "No transcript yet" : session.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !isActive {
                Text(session.relativeTimeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
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
