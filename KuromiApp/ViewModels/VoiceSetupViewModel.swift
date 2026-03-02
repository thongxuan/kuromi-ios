import Foundation
import Combine

enum VoiceGender: String, CaseIterable {
    case female = "female"; case male = "male"
    var label: String { self == .female ? "Nữ ♀" : "Nam ♂" }
}

enum VoiceAge: String, CaseIterable {
    case young = "young"; case middleAged = "middle_aged"; case old = "old"
    var label: String {
        switch self { case .young: return "Trẻ"; case .middleAged: return "Trưởng thành"; case .old: return "Già" }
    }
}

enum VoiceTone: String, CaseIterable {
    case high = "high"; case low = "low"
    var label: String { self == .high ? "Cao ↑" : "Trầm ↓" }
    var stability: Double { self == .high ? 0.3 : 0.75 }
    var highDescriptives: [String] { ["sassy","hyped","energetic","young","quirky"] }
    var lowDescriptives: [String] { ["classy","mature","professional","deep","resonant","warm"] }
}

class VoiceSetupViewModel: ObservableObject {
    // Filters
    @Published var filterGender: VoiceGender = .female
    @Published var filterAge: VoiceAge = .young
    @Published var filterTone: VoiceTone = .high
    @Published var filterDescription: String = ""
    @Published var selectedLanguage: STTLanguage = .vietnamese

    // Matched voices
    @Published var matchedVoices: [VoiceOption] = []
    @Published var selectedVoiceID: String = ""
    @Published var selectedVoiceName: String = ""
    @Published var isLoadingVoices: Bool = false
    @Published var voiceLoadError: String = ""

    @Published var wakeWord: String = "hey kuromi"
    @Published var trainingSamples: [String] = []
    @Published var currentTrainingStep: Int = 0
    @Published var isRecordingTraining: Bool = false
    @Published var trainingError: String = ""

    private var allVoices: [VoiceOption] = []
    private var elevenLabsService: ElevenLabsService?
    private let wakeWordService = WakeWordService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        if let settings = AppSettings.load() {
            selectedVoiceID = settings.selectedVoiceID
            selectedVoiceName = settings.selectedVoiceName
            wakeWord = settings.wakeWord.isEmpty ? "hey kuromi" : settings.wakeWord
            selectedLanguage = STTLanguage.from(code: settings.sttLanguage)
        }

        wakeWordService.onTrainingSampleCaptured = { [weak self] text in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.trainingSamples.append(text)
                self.isRecordingTraining = false
                if self.currentTrainingStep < 3 { self.currentTrainingStep += 1 }
            }
        }

        // Auto-filter when any input changes
        Publishers.CombineLatest4($filterGender, $filterAge, $filterTone, $filterDescription)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyFilters() }
            .store(in: &cancellables)
    }

    func setupElevenLabs(apiKey: String) {
        elevenLabsService = ElevenLabsService(apiKey: apiKey)
        loadVoices()
    }

    func loadVoices() {
        guard let service = elevenLabsService else { return }
        isLoadingVoices = true
        voiceLoadError = ""
        Task {
            do {
                let voiceList = try await service.fetchVoices()
                DispatchQueue.main.async {
                    self.allVoices = voiceList
                    self.isLoadingVoices = false
                    self.applyFilters()
                }
            } catch {
                DispatchQueue.main.async {
                    self.voiceLoadError = error.localizedDescription
                    self.isLoadingVoices = false
                }
            }
        }
    }

    func applyFilters() {
        let desc = filterDescription.lowercased().trimmingCharacters(in: .whitespaces)

        var scored: [(VoiceOption, Int)] = allVoices.map { voice in
            let labels = voice.labels ?? [:]
            var score = 0

            // Gender match (+3)
            if labels["gender"] == filterGender.rawValue { score += 3 }

            // Age match (+3)
            if labels["age"] == filterAge.rawValue { score += 3 }

            // Tone match (+2)
            let descriptive = (labels["descriptive"] ?? "").lowercased()
            let tonWords = filterTone == .high ? filterTone.highDescriptives : filterTone.lowDescriptives
            if tonWords.contains(where: { descriptive.contains($0) }) { score += 2 }

            // Description text match (+2 per keyword)
            if !desc.isEmpty {
                let keywords = desc.split(separator: " ").map(String.init)
                for kw in keywords {
                    if voice.name.lowercased().contains(kw) ||
                       descriptive.contains(kw) ||
                       (labels["accent"] ?? "").contains(kw) ||
                       (labels["use_case"] ?? "").contains(kw) { score += 2 }
                }
            }

            return (voice, score)
        }

        scored.sort { $0.1 > $1.1 }
        matchedVoices = scored.prefix(5).map { $0.0 }

        // Auto-select top match if nothing selected yet or current not in list
        if !matchedVoices.isEmpty {
            let ids = matchedVoices.map { $0.voice_id }
            if selectedVoiceID.isEmpty || !ids.contains(selectedVoiceID) {
                selectVoice(matchedVoices[0])
            }
        }
    }

    func selectVoice(_ voice: VoiceOption) {
        selectedVoiceID = voice.voice_id
        selectedVoiceName = voice.name
    }

    func previewVoice(_ voice: VoiceOption) {
        elevenLabsService?.previewVoice(voice)
    }

    // MARK: - Wake Word Training

    func startTrainingRecording() {
        guard currentTrainingStep < 3 else { return }
        isRecordingTraining = true
        trainingError = ""
        wakeWordService.recordTrainingSample()
    }

    func stopTrainingRecording() {
        wakeWordService.stopTrainingRecording()
        isRecordingTraining = false
    }

    func resetTraining() {
        trainingSamples = []
        currentTrainingStep = 0
        isRecordingTraining = false
    }

    var isTrainingComplete: Bool { currentTrainingStep >= 3 }

    func save() {
        guard var settings = AppSettings.load() else { return }
        settings.selectedVoiceID = selectedVoiceID
        settings.selectedVoiceName = selectedVoiceName
        settings.sttLanguage = selectedLanguage.code
        settings.wakeWord = computeFinalWakeWord()
        settings.save()
    }

    private func computeFinalWakeWord() -> String {
        guard !trainingSamples.isEmpty else { return wakeWord }
        // Use the most common/similar sample or just the first one
        return trainingSamples.first ?? wakeWord
    }
}
