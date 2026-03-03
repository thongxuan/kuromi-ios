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

                // Status label
                statusLabel
                    .padding(.bottom, 16)

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
            case .userSpeaking: return viewModel.currentTranscript.isEmpty ? "Listening…" : viewModel.currentTranscript
            case .aiSpeaking: return "Listening for your voice…"
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

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowRadius: CGFloat = 0

    // Fixed container size — circle scale từ center, không nhảy vị trí
    private let containerSize: CGFloat = 160

    private var circleScale: CGFloat {
        switch chatState {
        case .idle, .connecting, .error: return 0.55
        case .userSpeaking: return 0.75 + CGFloat(inputLevel) * 0.35
        case .aiSpeaking: return 0.65 * pulseScale
        }
    }

    private var orbColor: Color {
        switch chatState {
        case .idle: return Color.white.opacity(0.15)
        case .userSpeaking: return Color.purple.opacity(0.85)
        case .aiSpeaking: return Color.purple.opacity(0.5)
        case .connecting: return Color.white.opacity(0.07)
        case .error: return Color.red.opacity(0.4)
        }
    }

    private var glowColor: Color {
        switch chatState {
        case .userSpeaking: return .purple
        case .aiSpeaking: return Color.purple.opacity(0.5)
        default: return .clear
        }
    }

    var body: some View {
        ZStack {
            // Glow rings — cũng fixed center trong container
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(glowColor.opacity(max(0, 0.06 - Double(i) * 0.018)))
                    .frame(width: containerSize * circleScale + CGFloat(i * 28),
                           height: containerSize * circleScale + CGFloat(i * 28))
                    .opacity(chatState == .idle || chatState == .connecting ? 0 : 1)
            }

            // Main orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [orbColor, orbColor.opacity(0.5)]),
                        center: .center, startRadius: 0,
                        endRadius: containerSize * circleScale / 2
                    )
                )
                .frame(width: containerSize * circleScale, height: containerSize * circleScale)
                .shadow(color: glowColor, radius: glowRadius)
                .overlay(
                    Circle()
                        .strokeBorder(glowColor.opacity(0.4), lineWidth: 1.5)
                )
                .scaleEffect(circleScale / circleScale) // keep in place

            // Icon
            Image(systemName: orbIcon)
                .font(.system(size: 26, weight: .light))
                .foregroundColor(.white.opacity(0.65))
        }
        .frame(width: containerSize, height: containerSize) // fixed frame
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: circleScale)
        .animation(.easeInOut(duration: 0.4), value: orbColor)
        .onAppear { startAIPulse() }
        .onChange(of: chatState) { _, _ in startAIPulse() }
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

    private func startAIPulse() {
        guard case .aiSpeaking = chatState else {
            pulseScale = 1.0
            glowRadius = 0
            return
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.12
            glowRadius = 20
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
