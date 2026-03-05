import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                Spacer()

                // Transcript list
                TranscriptListView(
                    messages: viewModel.messages,
                    currentTranscript: viewModel.currentTranscript,
                    currentAIResponse: viewModel.currentAIResponse,
                    chatState: viewModel.chatState
                )
                .frame(maxHeight: 280)
                .padding(.horizontal, 20)

                Spacer()

                // Reconnect button
                if viewModel.showReconnectButton {
                    Button(action: { viewModel.reconnect() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reconnect")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.purple.opacity(0.7)))
                    }
                    .padding(.bottom, 12)

                }

                // Orb button (gộp orb + toggle)
                orbButton

                // Status label dưới orb
                statusLabel
                    .padding(.top, 8)
                    .padding(.bottom, 56)
            }
        }
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
                    .foregroundColor(.gray)
            }

            Spacer()

            // Speaker toggle
            Button(action: { viewModel.toggleSpeaker() }) {
                Image(systemName: viewModel.isLoudSpeaker ? "speaker.wave.3.fill" : "speaker.fill")
                    .font(.body)
                    .foregroundColor(viewModel.isLoudSpeaker ? .purple : .gray)
            }
            .padding(.trailing, 16)

            Button(action: { appState.openSetupEdit() }) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 8)
    }

    private var connectionColor: Color {
        switch viewModel.chatState {
        case .connecting: return .yellow
        case .idle, .userSpeaking, .aiSpeaking: return .green
        case .error: return .red
        }
    }

    private var connectionLabel: String {
        switch viewModel.chatState {
        case .connecting: return "Connecting…"
        case .idle: return "Connected"
        case .userSpeaking: return "Listening"
        case .aiSpeaking: return "Speaking"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    // MARK: - Status label

    @ViewBuilder
    private var statusLabel: some View {
        let label: String = {
            switch viewModel.chatState {
            case .connecting: return "Connecting to gateway…"
            case .idle: return "Tap to speak or say \"\(AppSettings.load()?.wakeWord ?? "hey kuromi")\""
            case .userSpeaking: return viewModel.currentTranscript.isEmpty ? "" : viewModel.currentTranscript
            case .aiSpeaking: return ""
            case .error(let msg): return msg
            }
        }()
        let color: Color = {
            switch viewModel.chatState {
            case .userSpeaking: return .white
            case .aiSpeaking: return .purple.opacity(0.7)
            case .error: return .red
            default: return .gray
            }
        }()
        Text(label)
            .font(.footnote)
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 32)
    
    }

    // MARK: - Orb Button

    private var orbButton: some View {
        Button(action: { viewModel.toggleSpeaking() }) {
            OrbView(chatState: viewModel.chatState, inputLevel: viewModel.inputLevel)
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

    private let containerSize: CGFloat = 160
    private let orbBase: CGFloat = 88

    // Orb scale reactive theo voice level khi user speaking
    private var orbScale: CGFloat {
        switch chatState {
        case .userSpeaking: return min(1.0 + CGFloat(inputLevel) * 3.0, 1.5)
        default: return 1.0
        }
    }

    private var orbColor: Color {
        switch chatState {
        case .idle, .connecting: return Color.white.opacity(0.13)
        case .userSpeaking: return Color.purple.opacity(0.88)
        case .aiSpeaking: return Color.purple.opacity(0.6)
        case .error: return Color.red.opacity(0.4)
        }
    }

    var body: some View {
        ZStack {
            // Sun rays (AI speaking only)
            if case .aiSpeaking = chatState {
                SunRaysView(orbRadius: orbBase / 2)
                    .frame(width: containerSize, height: containerSize)
            }

            // Breathing rings (user speaking)
            if case .userSpeaking = chatState {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.purple.opacity(0.12 - Double(i) * 0.04), lineWidth: 1)
                        .frame(width: orbBase * min(orbScale, 1.5) + CGFloat(i + 1) * 20,
                               height: orbBase * min(orbScale, 1.5) + CGFloat(i + 1) * 20)
                }
            }

            // Main orb — fixed size, chỉ scale
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [orbColor, orbColor.opacity(0.45)]),
                        center: .center, startRadius: 0, endRadius: orbBase / 2
                    )
                )
                .frame(width: orbBase, height: orbBase)
                .scaleEffect(orbScale)
                .shadow(color: orbColor, radius: orbScale > 1.05 ? 16 : 6)
                .animation(.spring(response: 0.12, dampingFraction: 0.5), value: orbScale)

            // Icon
            Image(systemName: orbIcon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white.opacity(0.7))
                .scaleEffect(orbScale > 1.0 ? min(orbScale, 1.15) : 1.0)
                .animation(.spring(response: 0.12, dampingFraction: 0.5), value: orbScale)
        }
        .frame(width: containerSize, height: containerSize)
        .animation(.easeInOut(duration: 0.35), value: orbColor)
    }

    private var orbIcon: String {
        switch chatState {
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .idle: return "waveform"
        case .userSpeaking: return "mic.fill"
        case .aiSpeaking: return "speaker.wave.2.fill"
        case .error: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Sun Rays (AI speaking)
struct SunRaysView: View {
    let orbRadius: CGFloat

    private let rayCount = 12
    private let segmentsPerRay = 3
    private let cycleDuration: Double = 3.5  // chậm hơn nữa
    private let maxReach: CGFloat = 44
    private let segLen: CGFloat = 8
    private let gap: CGFloat = 6

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let t = timeline.date.timeIntervalSinceReferenceDate
                // global phase 0→1 liên tục
                let globalPhase = CGFloat(t.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration)

                for rayIndex in 0..<rayCount {
                    let angle = Double(rayIndex) / Double(rayCount) * 2.0 * Double.pi
                    let cosA = CGFloat(Foundation.cos(angle))
                    let sinA = CGFloat(Foundation.sin(angle))

                    // offset mỗi ray lệch pha nhau để không đồng pha
                    let rayOffset = CGFloat(rayIndex) / CGFloat(rayCount)

                    for seg in 0..<segmentsPerRay {
                        // spacing lớn hơn = khoảng cách giữa các segment xa hơn
                        let segOffset = CGFloat(seg) * 0.38
                        var p = (globalPhase + segOffset + rayOffset * 0.25).truncatingRemainder(dividingBy: 1.0)

                        // dist: từ 0→maxReach trong một chu kỳ
                        let dist = gap + p * maxReach

                        // fade in 0→0.15, fade out 0.15→1.0 (fade out nhanh)
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
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: currentTranscript) { _, _ in
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
            if message.role == .assistant { Spacer() }

            Text(message.text)
                .font(.subheadline)
                .foregroundColor(message.role == .user ? .white : .purple.opacity(1.2))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.role == .user
                              ? Color.white.opacity(0.08)
                              : Color.purple.opacity(0.12))
                )
                .frame(maxWidth: 280, alignment: message.role == .user ? .leading : .trailing)

            if message.role == .user { Spacer() }
        }
        .opacity(opacity)
        .animation(.easeInOut(duration: 0.3), value: opacity)
    }
}

#Preview {
    ChatView()
        .environmentObject(AppState())
}
