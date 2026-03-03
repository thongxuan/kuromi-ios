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
                    .transition(.opacity)
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
            .animation(.easeInOut(duration: 0.2), value: label)
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

    @State private var rayRotation: Double = 0
    @State private var rayOpacity: Double = 0
    @State private var rayLengthScale: CGFloat = 0.8

    private let containerSize: CGFloat = 160
    private let orbBase: CGFloat = 88      // fixed orb size
    private let rayCount = 12

    // Orb scale reactive theo voice level khi user speaking
    private var orbScale: CGFloat {
        switch chatState {
        case .userSpeaking: return 1.0 + CGFloat(inputLevel) * 3.0
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
                ForEach(0..<rayCount, id: \.self) { i in
                    let angle = Double(i) / Double(rayCount) * 360.0
                    RayShape(
                        angle: angle + rayRotation,
                        orbRadius: orbBase / 2,
                        length: 18 * rayLengthScale,
                        width: 2.5
                    )
                    .stroke(Color.purple.opacity(rayOpacity * (i % 2 == 0 ? 1.0 : 0.55)),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }

            // Breathing rings (user speaking)
            if case .userSpeaking = chatState {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.purple.opacity(0.12 - Double(i) * 0.04), lineWidth: 1)
                        .frame(width: orbBase * orbScale + CGFloat(i + 1) * 20,
                               height: orbBase * orbScale + CGFloat(i + 1) * 20)
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
        .onAppear { updateAnimation() }
        .onChange(of: chatState) { _, _ in updateAnimation() }
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

    private func updateAnimation() {
        if case .aiSpeaking = chatState {
            // Rotate rays
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rayRotation = 360
            }
            // Fade + pulse rays
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                rayOpacity = 0.75
                rayLengthScale = 1.25
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                rayOpacity = 0
                rayLengthScale = 0.8
                rayRotation = 0
            }
        }
    }
}

// Hình dạng một tia sáng
struct RayShape: Shape {
    var angle: Double    // degrees
    var orbRadius: CGFloat
    var length: CGFloat
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rad = angle * Double.pi / 180
        let gap: CGFloat = 4
        let cosVal = CGFloat(Foundation.cos(rad))
        let sinVal = CGFloat(Foundation.sin(rad))
        let start = CGPoint(
            x: center.x + cosVal * (orbRadius + gap),
            y: center.y + sinVal * (orbRadius + gap)
        )
        let end = CGPoint(
            x: center.x + cosVal * (orbRadius + gap + length),
            y: center.y + sinVal * (orbRadius + gap + length)
        )
        var p = Path()
        p.move(to: start)
        p.addLine(to: end)
        return p
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

                    // Live transcript cursor
                    if case .userSpeaking = chatState, !currentTranscript.isEmpty {
                        HStack(alignment: .bottom, spacing: 0) {
                            Text(currentTranscript)
                                .foregroundColor(.white.opacity(0.9))
                            Text("▌")
                                .foregroundColor(.purple)
                                .opacity(1.0)
                                .animation(.easeInOut(duration: 0.5).repeatForever(), value: currentTranscript)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.12))
                        )
                        .id("live")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: currentTranscript) { _, _ in
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
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
