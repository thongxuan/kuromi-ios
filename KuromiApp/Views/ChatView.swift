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

                // Orb
                OrbView(
                    chatState: viewModel.chatState,
                    inputLevel: viewModel.inputLevel
                )
                .padding(.vertical, 32)

                // Status label
                statusLabel
                    .padding(.bottom, 24)

                // Transcript list
                TranscriptListView(
                    messages: viewModel.messages,
                    currentTranscript: viewModel.currentTranscript,
                    chatState: viewModel.chatState
                )
                .frame(maxHeight: 240)
                .padding(.horizontal, 20)

                Spacer()

                // Toggle button
                toggleButton
                    .padding(.horizontal, 40)
                    .padding(.bottom, 48)
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

            Button(action: { appState.currentScreen = .setup }) {
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

    private var statusLabel: some View {
        Group {
            switch viewModel.chatState {
            case .connecting:
                Text("Connecting to gateway…")
                    .foregroundColor(.gray)
            case .idle:
                Text("Tap to speak or say \"\(AppSettings.load()?.wakeWord ?? "hey kuromi")\"")
                    .foregroundColor(.gray)
            case .userSpeaking:
                Text(viewModel.currentTranscript.isEmpty ? "Listening…" : viewModel.currentTranscript)
                    .foregroundColor(.white)
                    .lineLimit(2)
            case .aiSpeaking:
                Text("Tap to interrupt")
                    .foregroundColor(.purple.opacity(0.7))
            case .error(let msg):
                Text(msg)
                    .foregroundColor(.red)
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .animation(.easeInOut(duration: 0.2), value: connectionLabel)
    }

    // MARK: - Toggle Button

    private var toggleButton: some View {
        Button(action: { viewModel.toggleSpeaking() }) {
            HStack(spacing: 12) {
                Image(systemName: toggleIcon)
                    .font(.title3)
                Text(toggleLabel)
                    .font(.headline)
            }
            .foregroundColor(toggleForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(toggleBackground)
            )
        }
        .disabled(!viewModel.isToggleEnabled)
        .opacity(viewModel.isToggleEnabled ? 1.0 : 0.4)
        .scaleEffect(viewModel.isToggleEnabled ? 1.0 : 0.97)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isToggleEnabled)
    }

    private var toggleIcon: String {
        switch viewModel.chatState {
        case .userSpeaking: return "stop.fill"
        case .aiSpeaking: return "hand.raised.fill"
        default: return "mic.fill"
        }
    }

    private var toggleLabel: String {
        switch viewModel.chatState {
        case .connecting: return "Connecting…"
        case .idle: return "Start Speaking"
        case .userSpeaking: return "Done Speaking"
        case .aiSpeaking: return "Interrupt"
        case .error: return "Reconnecting…"
        }
    }

    private var toggleForeground: Color {
        switch viewModel.chatState {
        case .userSpeaking: return .white
        case .aiSpeaking: return .white
        default: return .black
        }
    }

    private var toggleBackground: Color {
        switch viewModel.chatState {
        case .userSpeaking: return Color.purple
        case .aiSpeaking: return Color.purple.opacity(0.6)
        default: return Color.white
        }
    }
}

// MARK: - OrbView

struct OrbView: View {
    let chatState: ChatState
    let inputLevel: Float

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowRadius: CGFloat = 0

    private var baseSize: CGFloat {
        switch chatState {
        case .userSpeaking: return 140
        case .aiSpeaking: return 120
        default: return 90
        }
    }

    private var dynamicScale: CGFloat {
        switch chatState {
        case .userSpeaking:
            return 1.0 + CGFloat(inputLevel) * 0.5
        case .aiSpeaking:
            return pulseScale
        default:
            return 1.0
        }
    }

    private var orbColor: Color {
        switch chatState {
        case .idle: return Color.white.opacity(0.12)
        case .userSpeaking: return Color.purple.opacity(0.85)
        case .aiSpeaking: return Color.purple.opacity(0.45)
        case .connecting: return Color.white.opacity(0.06)
        case .error: return Color.red.opacity(0.3)
        }
    }

    private var glowColor: Color {
        switch chatState {
        case .userSpeaking: return .purple
        case .aiSpeaking: return Color.purple.opacity(0.6)
        default: return .clear
        }
    }

    var body: some View {
        ZStack {
            // Glow rings
            if case .userSpeaking = chatState {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.purple.opacity(0.06 - Double(i) * 0.015))
                        .frame(width: baseSize * dynamicScale + CGFloat(i * 30),
                               height: baseSize * dynamicScale + CGFloat(i * 30))
                }
            }
            if case .aiSpeaking = chatState {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .fill(Color.purple.opacity(0.05 - Double(i) * 0.01))
                        .frame(width: baseSize * pulseScale + CGFloat(i * 24),
                               height: baseSize * pulseScale + CGFloat(i * 24))
                }
            }

            // Main orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [orbColor.opacity(1.2), orbColor.opacity(0.6)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: baseSize / 2
                    )
                )
                .frame(width: baseSize * dynamicScale, height: baseSize * dynamicScale)
                .shadow(color: glowColor, radius: glowRadius)
                .overlay(
                    Circle()
                        .strokeBorder(glowColor.opacity(0.4), lineWidth: 1.5)
                        .frame(width: baseSize * dynamicScale, height: baseSize * dynamicScale)
                )

            // Inner icon
            Image(systemName: orbIcon)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white.opacity(0.6))
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: dynamicScale)
        .animation(.easeInOut(duration: 0.5), value: orbColor)
        .onAppear { startAIPulse() }
        .onChange(of: chatState.description) { _, _ in startAIPulse() }
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

extension ChatState {
    var description: String {
        switch self {
        case .connecting: return "connecting"
        case .idle: return "idle"
        case .userSpeaking: return "userSpeaking"
        case .aiSpeaking: return "aiSpeaking"
        case .error(let e): return "error:\(e)"
        }
    }
}

// MARK: - TranscriptListView

struct TranscriptListView: View {
    let messages: [Message]
    let currentTranscript: String
    let chatState: ChatState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        TranscriptBubble(message: message, opacity: bubbleOpacity(index: index))
                            .id(message.id)
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
                .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: message.role == .user ? .leading : .trailing)

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
