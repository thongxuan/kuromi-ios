import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ChatViewModel()
    @State private var showText: Bool = false

    var body: some View {
        ZStack {
            // Background
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                Spacer()

                // Transcript list — only shown when showText is true
                if showText {
                    TranscriptListView(
                        messages: viewModel.messages,
                        currentTranscript: viewModel.currentTranscript,
                        currentAIResponse: viewModel.currentAIResponse,
                        chatState: viewModel.chatState
                    )
                    .frame(maxHeight: 280)
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    Spacer()
                }

                // Orb button
                orbButton

                // Status label below orb
                statusLabel
                    .padding(.top, 8)

                // Reconnect button — below orb
                if viewModel.showReconnectButton {
                    Button(action: { viewModel.reconnect() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reconnect")
                        }
                        .font(.subheadline)
                        .foregroundColor(.appLabel)
                        .padding(.horizontal, 24)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.purple.opacity(0.7)))
                    }
                    .padding(.top, 12)
                }

                Spacer()
            }
        }
        .safeAreaPadding([.horizontal, .bottom])
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Status dot
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(connectionLabel)
                    .font(.caption)
                    .foregroundColor(.appSecondaryLabel)
            }

            Spacer()

            // Text toggle
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    showText.toggle()
                }
            }) {
                Image(systemName: showText ? "text.bubble.fill" : "text.bubble")
                    .font(.body)
                    .foregroundColor(showText ? .purple : .gray)
            }
            .padding(.trailing, 12)

            // Speaker toggle
            Button(action: { viewModel.toggleSpeaker() }) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.body)
                    .foregroundColor(viewModel.isLoudSpeaker ? .purple : .gray)
            }
            .padding(.trailing, 16)

            Button(action: { appState.openSetupEdit() }) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundColor(.appSecondaryLabel)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 8)
    }

    private var connectionColor: Color {
        switch viewModel.chatState {
        case .connecting: return .yellow
        case .idle, .listening, .aiThinking, .aiSpeaking: return .green
        case .error: return .red
        }
    }

    private var connectionLabel: String {
        switch viewModel.chatState {
        case .connecting: return "Connecting..."
        case .idle: return "Connected"
        case .listening: return "Listening"
        case .aiThinking: return "Thinking"
        case .aiSpeaking: return "Speaking"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    // MARK: - Status label

    @ViewBuilder
    private var statusLabel: some View {
        let label: String = {
            switch viewModel.chatState {
            case .connecting: return "Connecting to gateway..."
            case .idle: return viewModel.wakePhrase.isEmpty ? "Tap to speak" : "Tap or say '\(viewModel.wakePhrase)'"
            case .listening: return "Listening..."
            case .aiThinking: return "Thinking..."
            case .aiSpeaking: return "Speaking..."
            case .error(let msg): return msg
            }
        }()
        let color: Color = {
            switch viewModel.chatState {
            case .listening: return Color.appLabel.opacity(0.5)
            case .aiThinking: return .orange.opacity(0.5)
            case .aiSpeaking: return .purple.opacity(0.5)
            case .error: return .red
            default: return .gray
            }
        }()
        let visible: Bool = !viewModel.isSessionActive && viewModel.chatState != .listening
        Text(label)
            .font(.footnote)
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 32)
            .opacity(visible ? 1 : 0)  // hide via opacity — keeps layout stable
    }

    // MARK: - Orb Button

    private var orbButton: some View {
        Button(action: { viewModel.toggleSpeaking() }) {
            OrbView(chatState: viewModel.chatState, inputLevel: viewModel.inputLevel, isSessionActive: viewModel.isSessionActive, isRelayMode: !viewModel.isOnDeviceMode)
        }
        .disabled(!viewModel.isToggleEnabled)
        .opacity(viewModel.isToggleEnabled ? 1.0 : 0.5)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isToggleEnabled)
    }
}

// MARK: - OrbView

struct OrbView: View {
    let chatState: ChatState
    let inputLevel: Float
    let isSessionActive: Bool
    var isRelayMode: Bool = false

    private let containerSize: CGFloat = 240
    private let orbBase: CGFloat = 132

    @State private var thinkingRotation: Double = 0
    @State private var thinkingPulse: CGFloat = 1.0

    // 3 visual states: idle | userSpeaking | ai
    private enum OrbVisual { case idle, userSpeaking, ai }
    private var visual: OrbVisual {
        guard isSessionActive else { return .idle }
        switch chatState {
        case .listening: return .userSpeaking
        default: return .ai
        }
    }

    // Orb scale reactive to voice level when listening
    private var orbScale: CGFloat {
        visual == .userSpeaking ? min(1.0 + CGFloat(inputLevel) * 3.0, 1.5) : 1.0
    }

    private var orbColor: Color {
        switch visual {
        case .idle: return Color.appLabel.opacity(0.13)
        case .userSpeaking: return Color.gray.opacity(0.6)
        case .ai: return Color.appAccent.opacity(0.75)
        }
    }

    var body: some View {
        ZStack {
            // Breathing rings — user speaking
            if visual == .userSpeaking {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.gray.opacity(0.15 - Double(i) * 0.05), lineWidth: 1)
                        .frame(width: orbBase * min(orbScale, 1.5) + CGFloat(i + 1) * 20,
                               height: orbBase * min(orbScale, 1.5) + CGFloat(i + 1) * 20)
                }
            }

            // Rotating arc + pulse — AI (thinking/speaking)
            if visual == .ai {

                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(orbColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: orbBase + 16, height: orbBase + 16)
                    .rotationEffect(.degrees(thinkingRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            thinkingRotation = 360
                        }
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            thinkingPulse = 1.08
                        }
                    }
                    .onDisappear { thinkingRotation = 0; thinkingPulse = 1.0 }
            }

            // Main orb
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [orbColor, orbColor.opacity(0.45)]),
                    center: .center, startRadius: 0, endRadius: orbBase / 2
                ))
                .frame(width: orbBase, height: orbBase)
                .scaleEffect(visual == .ai ? thinkingPulse : orbScale)
                .shadow(color: orbColor, radius: orbScale > 1.05 ? 16 : 6)
                .animation(.spring(response: 0.12, dampingFraction: 0.5), value: orbScale)

            // Icon — fixed center, no scale animation
            if !orbIcon.isEmpty {
                Image(systemName: orbIcon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.appLabel.opacity(0.7))
                    .frame(width: orbBase, height: orbBase)  // match orb size to guarantee center
                    .animation(nil, value: orbIcon)  // no animation on icon change
            }
        }
        .frame(width: containerSize, height: containerSize)
        .animation(.easeInOut(duration: 0.35), value: visual == .idle)
    }

    private var orbIcon: String {
        switch visual {
        case .idle: return isRelayMode ? "antenna.radiowaves.left.and.right" : "waveform"
        case .userSpeaking: return "mic.fill"
        case .ai: return ""  // arc animation speaks for itself
        }
    }
}

// MARK: - Pulsing Ring View (for aiThinking state)

// MARK: - Sun Rays (AI speaking)
struct SunRaysView: View {
    let orbRadius: CGFloat

    private let rayCount = 12
    private let segmentsPerRay = 3
    private let cycleDuration: Double = 3.5
    private let maxReach: CGFloat = 44
    private let segLen: CGFloat = 8
    private let gap: CGFloat = 6

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let t = timeline.date.timeIntervalSinceReferenceDate
                let globalPhase = CGFloat(t.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration)

                for rayIndex in 0..<rayCount {
                    let angle = Double(rayIndex) / Double(rayCount) * 2.0 * Double.pi
                    let cosA = CGFloat(Foundation.cos(angle))
                    let sinA = CGFloat(Foundation.sin(angle))
                    let rayOffset = CGFloat(rayIndex) / CGFloat(rayCount)

                    for seg in 0..<segmentsPerRay {
                        let segOffset = CGFloat(seg) * 0.38
                        let p = (globalPhase + segOffset + rayOffset * 0.25).truncatingRemainder(dividingBy: 1.0)
                        let dist = gap + p * maxReach

                        let fadeIn: Double = min(Double(p) / 0.15, 1.0)
                        let fadeOut: Double = max(1.0 - (Double(p) - 0.15) / 0.85, 0.0)
                        let opacity = fadeIn * fadeOut * 0.9

                        let sx = center.x + cosA * (orbRadius + dist)
                        let sy = center.y + sinA * (orbRadius + dist)
                        let ex = center.x + cosA * (orbRadius + dist + segLen)
                        let ey = center.y + sinA * (orbRadius + dist + segLen)

                        var path = Path()
                        path.move(to: CGPoint(x: sx, y: sy))
                        path.addLine(to: CGPoint(x: ex, y: ey))
                        context.stroke(path,
                                       with: .color(.purple.opacity(opacity)),
                                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                }
            }
        }
    }
}

// MARK: - TranscriptListView

struct TranscriptListView: View {
    let messages: [Message]
    let currentTranscript: String
    let currentAIResponse: String
    let chatState: ChatState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        TranscriptBubble(message: message, opacity: bubbleOpacity(index: index))
                            .id(message.id)
                    }

                    // AI streaming response
                    if !currentAIResponse.isEmpty {
                        Text(currentAIResponse)
                            .foregroundColor(.purple.opacity(0.9))
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.08)))
                            .id("ai-live")
                    }

                    // Live transcript cursor — hidden per design
                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: currentTranscript) {
                proxy.scrollTo("live", anchor: .bottom)
            }
        }
    }

    private func bubbleOpacity(index: Int) -> Double {
        let total = messages.count
        guard total > 0 else { return 1.0 }
        let distFromEnd = total - 1 - index
        switch distFromEnd {
        case 0: return 1.0
        case 1: return 0.7
        case 2: return 0.4
        default: return 0.2
        }
    }
}

struct TranscriptBubble: View {
    let message: Message
    let opacity: Double

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            Text(message.text)
                .font(.subheadline)
                .foregroundColor(message.role == .user ? .appLabel : .purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.role == .user
                              ? Color.appLabel.opacity(0.08)
                              : Color.purple.opacity(0.12))
                )
                .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer() }
        }
        .opacity(opacity)
        .animation(.easeInOut(duration: 0.3), value: opacity)
    }
}

#Preview {
    ChatView()
        .environmentObject(AppState())
}
