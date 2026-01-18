import SwiftUI

struct TranscriptView: View {
    let session: Session
    @Environment(AppState.self) private var appState
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @State private var selectedLines: Set<UUID> = []
    @State private var isAutoScrollEnabled = true
    @State private var scrollProxy: ScrollViewProxy?
    @State private var scrollViewHeight: CGFloat = 0

    private var isRecording: Bool {
        appState.recordingState == .recording
    }

    private var hasMicRecording: Bool {
        transcriptionService.isMicActive
    }

    private var hasAppRecording: Bool {
        transcriptionService.isAppActive
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(session.lines.filter { !$0.text.isEmpty }) { line in
                            TranscriptLineView(
                                line: line,
                                isSelected: selectedLines.contains(line.id),
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

            // Waveform panel at bottom while recording
            if isRecording {
                RecordingWaveformPanel(
                    micLevels: transcriptionService.micAudioLevels,
                    appLevels: transcriptionService.appAudioLevels,
                    hasMic: hasMicRecording,
                    hasApp: hasAppRecording,
                    appName: appState.selectedAppName
                )
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

/// Continuous wave audio visualization using Canvas for performance
struct ContinuousWaveView: View {
    let levels: [Float]
    let color: Color
    let label: String?

    private let waveHeight: CGFloat = 40
    private let minAmplitude: CGFloat = 2
    private let downsampleFactor = 2  // Skip every Nth point for performance

    init(levels: [Float], color: Color, label: String? = nil) {
        self.levels = levels
        self.color = color
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midY = height / 2

                // Downsample levels for performance
                let sampledLevels: [Float]
                if levels.count > downsampleFactor {
                    sampledLevels = stride(from: 0, to: levels.count, by: downsampleFactor).map { levels[$0] }
                } else {
                    sampledLevels = levels
                }

                guard sampledLevels.count > 1 else {
                    // Draw flat line if no data
                    var centerLine = Path()
                    centerLine.move(to: CGPoint(x: 0, y: midY))
                    centerLine.addLine(to: CGPoint(x: width, y: midY))
                    context.stroke(centerLine, with: .color(color.opacity(0.3)), lineWidth: 1)
                    return
                }

                let stepX = width / CGFloat(sampledLevels.count - 1)

                // Build wave path
                var wavePath = Path()
                let firstAmplitude = max(minAmplitude, CGFloat(sampledLevels[0]) * (height / 2 - minAmplitude))
                wavePath.move(to: CGPoint(x: 0, y: midY - firstAmplitude))

                // Upper wave
                for i in 1..<sampledLevels.count {
                    let x = CGFloat(i) * stepX
                    let amplitude = max(minAmplitude, CGFloat(sampledLevels[i]) * (height / 2 - minAmplitude))
                    let y = midY - amplitude
                    let prevX = CGFloat(i - 1) * stepX
                    let controlX = (prevX + x) / 2
                    wavePath.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: controlX, y: y))
                }

                // Lower wave (mirror)
                for i in (0..<sampledLevels.count).reversed() {
                    let x = CGFloat(i) * stepX
                    let amplitude = max(minAmplitude, CGFloat(sampledLevels[i]) * (height / 2 - minAmplitude))
                    let y = midY + amplitude

                    if i == sampledLevels.count - 1 {
                        wavePath.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        let nextX = CGFloat(i + 1) * stepX
                        let controlX = (nextX + x) / 2
                        wavePath.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: controlX, y: y))
                    }
                }
                wavePath.closeSubpath()

                // Draw filled wave
                context.fill(wavePath, with: .color(color.opacity(0.6)))

                // Draw center line
                var centerLine = Path()
                centerLine.move(to: CGPoint(x: 0, y: midY))
                centerLine.addLine(to: CGPoint(x: width, y: midY))
                context.stroke(centerLine, with: .color(color.opacity(0.3)), lineWidth: 1)
            }
            .frame(height: waveHeight)
            .drawingGroup()  // Render to Metal for performance
        }
    }
}

/// Container for side-by-side waveforms at bottom of transcript
struct RecordingWaveformPanel: View {
    let micLevels: [Float]
    let appLevels: [Float]
    let hasMic: Bool
    let hasApp: Bool
    let appName: String?

    var body: some View {
        HStack(spacing: 16) {
            if hasMic {
                ContinuousWaveView(
                    levels: micLevels,
                    color: .blue,
                    label: "You"
                )
            }

            if hasApp {
                ContinuousWaveView(
                    levels: appLevels,
                    color: .green,
                    label: appName ?? "App"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

/// Animated waveform indicator for transcription states
struct WaveformIndicator: View {
    let state: AppState.TranscriptionState
    @State private var animating = false

    let barCount = 3
    let barWidth: CGFloat = 2
    let barSpacing: CGFloat = 2
    let minHeight: CGFloat = 4
    let maxHeight: CGFloat = 12

    private var animationDuration: Double {
        switch state {
        case .listening: return 0.6    // Slower pulse when listening
        case .processing: return 0.25  // Faster pulse when processing
        case .idle: return 0.4
        }
    }

    private var barColor: Color {
        switch state {
        case .listening: return .green.opacity(0.7)
        case .processing: return .orange.opacity(0.8)
        case .idle: return .gray.opacity(0.5)
        }
    }

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor)
                    .frame(width: barWidth, height: animating ? maxHeight : minHeight)
                    .animation(
                        .easeInOut(duration: animationDuration)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .frame(height: maxHeight)
        .onAppear { animating = true }
        .onChange(of: state) { _, _ in
            // Reset animation when state changes
            animating = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animating = true
            }
        }
    }
}

struct TranscriptLineView: View {
    @Environment(AppState.self) private var appState
    let line: TranscriptLine
    let isSelected: Bool
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

            // Text Content + Copy Button inline
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(line.text)
                    .font(.body)
                    .textSelection(.enabled)

                if isHovered {
                    // Copy Button (inline after text, only visible on hover)
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
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
