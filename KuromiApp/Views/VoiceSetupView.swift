import SwiftUI

struct VoiceSetupView: View {
    @EnvironmentObject var appState: AppState
    var isEditMode: Bool = false
    @StateObject private var viewModel = VoiceSetupViewModel()
    @State private var showingSaveConfirm = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

            VStack(spacing: 0) {
                // Navigation Bar
                HStack {
                    Button(action: { appState.currentScreen = .setup }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.purple)
                        .font(.body)
                    }
                    Spacer()
                    Text("Voice Setup")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Save") {
                        viewModel.save()
                        appState.isSetupEditMode = false
                        appState.currentScreen = .chat
                    }
                    .foregroundColor(.purple)
                    .font(.body)
                    .disabled(!canSave)
                    .opacity(canSave ? 1.0 : 0.4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView {
                    VStack(spacing: 28) {
                        // Wake Word Training Section
                        wakeWordSection

                        Divider().background(Color.white.opacity(0.1))

                        // Voice Selection Section
                        voiceSelectionSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            if let settings = AppSettings.load(), !settings.elevenLabsAPIKey.isEmpty {
                viewModel.setupElevenLabs(apiKey: settings.elevenLabsAPIKey)
            } else {
                viewModel.voiceLoadError = "ElevenLabs API key not set. Please go back and enter it."
            }
        }
    }

    private var canSave: Bool {
        !viewModel.selectedVoiceID.isEmpty
    }

    // MARK: - Wake Word Section

    private var wakeWordSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wake Word")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Train Kuromi to recognize your voice")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            // Wake phrase text input
            VStack(alignment: .leading, spacing: 6) {
                Text("Wake phrase")
                    .font(.caption)
                    .foregroundColor(.gray)
                TextField("e.g. hey kuromi", text: $viewModel.wakeWord)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1))
                    )
            }

            // Training progress
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { step in
                    TrainingStepView(
                        stepIndex: step,
                        isCompleted: step < viewModel.currentTrainingStep,
                        isCurrent: step == viewModel.currentTrainingStep && !viewModel.isTrainingComplete
                    )
                }
            }

            // Record button
            if !viewModel.isTrainingComplete {
                Button(action: {
                    if viewModel.isRecordingTraining {
                        viewModel.stopTrainingRecording()
                    } else {
                        viewModel.startTrainingRecording()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isRecordingTraining ? "stop.fill" : "mic.fill")
                        Text(viewModel.isRecordingTraining ? "Stop Recording" : "Record Sample \(viewModel.currentTrainingStep + 1)/3")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(viewModel.isRecordingTraining ? .white : .purple)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.isRecordingTraining ? Color.red.opacity(0.8) : Color.purple.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(viewModel.isRecordingTraining ? Color.red : Color.purple.opacity(0.4), lineWidth: 1)
                    )
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Wake word trained!")
                        .foregroundColor(.green)
                    Spacer()
                    Button("Reset") {
                        viewModel.resetTraining()
                    }
                    .font(.caption)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.15)))
                }
                .padding(.vertical, 8)
            }

            if !viewModel.trainingError.isEmpty {
                Text(viewModel.trainingError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Skip option
            Button("Skip wake word training") {
                appState.currentScreen = .chat
            }
            .font(.caption)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Voice Selection Section

    private var voiceSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Choose ElevenLabs voice for AI responses")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            if viewModel.isLoadingVoices {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.purple)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if !viewModel.voiceLoadError.isEmpty {
                VStack(spacing: 8) {
                    Text(viewModel.voiceLoadError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") { viewModel.loadVoices() }
                        .foregroundColor(.purple)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.voices) { voice in
                        VoiceRowView(
                            voice: voice,
                            isSelected: viewModel.selectedVoiceID == voice.voice_id,
                            onSelect: { viewModel.selectVoice(voice) },
                            onPreview: { viewModel.previewVoice(voice) }
                        )
                    }
                }
            }
        }
    }
}

struct TrainingStepView: View {
    let stepIndex: Int
    let isCompleted: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green.opacity(0.2) : (isCurrent ? Color.purple.opacity(0.2) : Color.white.opacity(0.05)))
                    .frame(width: 40, height: 40)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                } else {
                    Text("\(stepIndex + 1)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isCurrent ? .purple : .gray)
                }
            }
            Text("Take \(stepIndex + 1)")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

struct VoiceRowView: View {
    let voice: VoiceOption
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.purple : Color.white.opacity(0.07))
                            .frame(width: 36, height: 36)
                        Image(systemName: isSelected ? "checkmark" : "person.fill")
                            .font(.caption)
                            .foregroundColor(isSelected ? .white : .gray)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        if !voice.categoryLabel.isEmpty {
                            Text(voice.categoryLabel)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                }
            }

            Button(action: onPreview) {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundColor(.purple.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.purple.opacity(0.1) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        )
    }
}

#Preview {
    VoiceSetupView()
        .environmentObject(AppState())
}
