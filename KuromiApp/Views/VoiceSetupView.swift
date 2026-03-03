import SwiftUI

struct VoiceSetupView: View {
    @EnvironmentObject var appState: AppState
    var isEditMode: Bool = false
    @StateObject private var viewModel = VoiceSetupViewModel()
    @State private var showingSaveConfirm = false
    @State private var showLanguagePicker = false
    @State private var languageSearch = ""

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
                        // Language Section
                        languageSection

                        Divider().background(Color.white.opacity(0.1))

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
            if let settings = AppSettings.load() {
                viewModel.setupOpenAI(apiKey: settings.openAIKey)
            }
        }
    }

    private var canSave: Bool {
        !viewModel.selectedVoiceID.isEmpty && !viewModel.matchedVoices.isEmpty
    }

    // MARK: - Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ngôn ngữ nhận giọng")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Ngôn ngữ chính anh/chị sẽ nói")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Button(action: { showLanguagePicker = true }) {
                HStack {
                    Text(viewModel.selectedLanguage.flag)
                        .font(.title3)
                    Text(viewModel.selectedLanguage.name)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1))
                )
            }
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(
                search: $languageSearch,
                selected: $viewModel.selectedLanguage,
                onDismiss: { showLanguagePicker = false }
            )
        }
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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Tuỳ chỉnh giọng AI theo sở thích")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            do {
                // Filter controls
                VStack(spacing: 14) {
                    // Gender
                    VoiceFilterRow(label: "Giới tính") {
                        ForEach(VoiceGender.allCases, id: \.rawValue) { g in
                            RadioChip(title: g.label, isSelected: viewModel.filterGender == g) {
                                viewModel.filterGender = g
                            }
                        }
                    }

                    // Age
                    VoiceFilterRow(label: "Độ tuổi") {
                        ForEach(VoiceAge.allCases, id: \.rawValue) { a in
                            RadioChip(title: a.label, isSelected: viewModel.filterAge == a) {
                                viewModel.filterAge = a
                            }
                        }
                    }

                    // Tone
                    VoiceFilterRow(label: "Tone giọng") {
                        ForEach(VoiceTone.allCases, id: \.rawValue) { t in
                            RadioChip(title: t.label, isSelected: viewModel.filterTone == t) {
                                viewModel.filterTone = t
                            }
                        }
                    }

                    // Description text
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mô tả thêm")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextField("vd: warm, british, storyteller...", text: $viewModel.filterDescription)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                            )
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))

                // Top matched voices
                if viewModel.matchedVoices.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Không tìm thấy giọng phù hợp. Thử thay đổi bộ lọc.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Giọng phù hợp nhất")
                            .font(.caption)
                            .foregroundColor(.gray)

                        ForEach(viewModel.matchedVoices, id: \.id) { voice in
                            VoiceRowView(
                                voice: voice,
                                isSelected: viewModel.selectedVoiceID == voice.id,
                                onSelect: { viewModel.selectVoice(voice) },
                                onPreview: { viewModel.previewVoice(voice) }
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Filter Components

struct VoiceFilterRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            HStack(spacing: 8) {
                content()
            }
        }
    }
}

struct RadioChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.purple : Color.white.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    if isSelected {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white : .gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.purple.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isSelected ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1))
            )
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
    let voice: OpenAIVoiceOption
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
                        Text(voice.descriptives.prefix(2).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundColor(.gray)
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

struct LanguagePickerSheet: View {
    @Binding var search: String
    @Binding var selected: STTLanguage
    let onDismiss: () -> Void
    @State private var localSelected: STTLanguage = STTLanguage.popular[0]

    private var filtered: [STTLanguage] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return STTLanguage.popular }
        return STTLanguage.popular.filter {
            $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Tìm ngôn ngữ...", text: $search)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if filtered.isEmpty {
                        Spacer()
                        Text("Không tìm thấy ngôn ngữ")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                        Spacer()
                    } else {
                        List(filtered) { lang in
                            Button(action: {
                                localSelected = lang
                                selected = lang
                                search = ""
                                onDismiss()
                            }) {
                                HStack(spacing: 12) {
                                    Text(lang.flag).font(.title3)
                                    Text(lang.name)
                                        .foregroundColor(.white)
                                        .font(.body)
                                    Spacer()
                                    if localSelected.code == lang.code {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.purple)
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.white.opacity(localSelected.code == lang.code ? 0.08 : 0.04))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .onAppear { localSelected = selected }
            .navigationTitle("Chọn ngôn ngữ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") { search = ""; onDismiss() }
                        .foregroundColor(.purple)
                }
            }
        }
    }
}

#Preview {
    VoiceSetupView()
        .environmentObject(AppState())
}
