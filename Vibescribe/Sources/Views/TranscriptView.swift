import SwiftUI

struct TranscriptView: View {
    let session: Session
    @Environment(AppState.self) private var appState
    @State private var selectedLines: Set<UUID> = []
    @State private var isAutoScrollEnabled = true
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.lines) { line in
                        TranscriptLineView(
                            line: line,
                            isSelected: selectedLines.contains(line.id),
                            onCopy: { copyLine(line) },
                            onSelect: { toggleSelection(line) }
                        )
                        .id(line.id)
                    }
                }
                .padding()
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: session.lines.count) { _, _ in
                if isAutoScrollEnabled, let lastLine = session.lines.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastLine.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func toggleSelection(_ line: TranscriptLine) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedLines.contains(line.id) {
                selectedLines.remove(line.id)
            } else {
                selectedLines.insert(line.id)
            }
        } else {
            selectedLines = [line.id]
        }
    }

    private func copyLine(_ line: TranscriptLine) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line.text, forType: .string)
        appState.showToast("Copied to clipboard")
    }

}

struct TranscriptLineView: View {
    let line: TranscriptLine
    let isSelected: Bool
    let onCopy: () -> Void
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Source Label
            Text(line.source.displayLabel + ":")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(line.source == .you ? .blue : .green)
                .frame(width: 60, alignment: .trailing)

            // Text Content
            Text(line.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Copy Button
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
            .help("Copy line")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
    }
}

#Preview {
    let session = Session()
    session.lines = [
        TranscriptLine(text: "Hey, how's the project going?", source: .you, sessionId: session.id),
        TranscriptLine(text: "It's going well! Just finished the main feature.", source: .remote, sessionId: session.id),
        TranscriptLine(text: "That's great to hear. Any blockers?", source: .you, sessionId: session.id),
        TranscriptLine(text: "Not really, just need to write some tests and we should be good.", source: .remote, sessionId: session.id)
    ]

    return TranscriptView(session: session)
        .environment(AppState())
        .frame(width: 500, height: 400)
}
