import SwiftUI

struct TranscriptView: View {
    let session: Session
    @Environment(AppState.self) private var appState
    @State private var selectedLines: Set<UUID> = []
    @State private var isAutoScrollEnabled = true
    @State private var scrollProxy: ScrollViewProxy?
    @State private var scrollViewHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.lines) { line in
                        TranscriptLineView(
                            line: line,
                            isSelected: selectedLines.contains(line.id),
                            isActive: appState.activeLineIds.contains(line.id),
                            onCopy: { copyLine(line) },
                            onSelect: { toggleSelection(line) }
                        )
                        .id(line.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: TranscriptBottomOffsetKey.self,
                                    value: geo.frame(in: .named("transcriptScroll")).maxY
                                )
                            }
                        )
                }
                .padding()
            }
            .coordinateSpace(name: "transcriptScroll")
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { scrollViewHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, newValue in
                            scrollViewHeight = newValue
                        }
                }
            )
            .background(
                Button("Copy Selected") {
                    copySelectedLines()
                }
                .keyboardShortcut("c", modifiers: .command)
                .opacity(0)
            )
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
            .onPreferenceChange(TranscriptBottomOffsetKey.self) { bottomOffset in
                let distanceToBottom = bottomOffset - scrollViewHeight
                isAutoScrollEnabled = distanceToBottom <= 50
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

    private func copySelectedLines() {
        let linesToCopy = session.lines.filter { selectedLines.contains($0.id) }
        guard !linesToCopy.isEmpty else { return }

        let text = linesToCopy.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appState.showToast("Copied \(linesToCopy.count) line\(linesToCopy.count == 1 ? "" : "s")")
    }

}

private struct TranscriptBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Animated waveform indicator for active transcription
struct WaveformIndicator: View {
    @State private var animating = false

    let barCount = 3
    let barWidth: CGFloat = 2
    let barSpacing: CGFloat = 2
    let minHeight: CGFloat = 4
    let maxHeight: CGFloat = 12

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: barWidth, height: animating ? maxHeight : minHeight)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(height: maxHeight)
        .onAppear { animating = true }
    }
}

struct TranscriptLineView: View {
    @Environment(AppState.self) private var appState
    let line: TranscriptLine
    let isSelected: Bool
    let isActive: Bool
    let onCopy: () -> Void
    let onSelect: () -> Void

    @State private var isHovered = false

    private var speakerLabel: String {
        appState.speakerDisplayLabel(for: line.speaker)
    }

    private var labelWidth: CGFloat {
        // Dynamic width based on label length
        let label = speakerLabel
        if label.count <= 4 {
            return 50
        } else if label.count <= 12 {
            return 100
        } else {
            return 150
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Speaker Label with color
            Text(speakerLabel + ":")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(line.speaker.color)
                .frame(minWidth: labelWidth, alignment: .trailing)

            // Text Content + Waveform/Copy Button inline
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(line.text)
                    .font(.body)
                    .textSelection(.enabled)

                if isActive {
                    // Animated waveform for active transcription
                    WaveformIndicator()
                } else if isHovered {
                    // Copy Button (inline after text, only visible on hover)
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy line")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

#Preview {
    let session = Session()
    session.lines = [
        TranscriptLine(text: "Hey, how's the project going?", speaker: .you, sessionId: session.id),
        TranscriptLine(text: "It's going well! Just finished the main feature.", speaker: .remote(speakerIndex: 0), sessionId: session.id),
        TranscriptLine(text: "That's great to hear. Any blockers?", speaker: .you, sessionId: session.id),
        TranscriptLine(text: "Not really, just need to write some tests.", speaker: .remote(speakerIndex: 0), sessionId: session.id),
        TranscriptLine(text: "I have a different approach to suggest.", speaker: .remote(speakerIndex: 1), sessionId: session.id)
    ]

    return TranscriptView(session: session)
        .environment(AppState())
        .frame(width: 500, height: 400)
}
