import Foundation
import Combine

class VoiceSetupViewModel: ObservableObject {
    @Published var voices: [VoiceOption] = []
    @Published var selectedVoiceID: String = ""
    @Published var selectedVoiceName: String = ""
    @Published var isLoadingVoices: Bool = false
    @Published var voiceLoadError: String = ""

    @Published var wakeWord: String = "hey kuromi"
    @Published var trainingSamples: [String] = [] // recognized texts from 3 recordings
    @Published var currentTrainingStep: Int = 0 // 0-2
    @Published var isRecordingTraining: Bool = false
    @Published var trainingError: String = ""

    private var elevenLabsService: ElevenLabsService?
    private let wakeWordService = WakeWordService()

    init() {
        if let settings = AppSettings.load() {
            selectedVoiceID = settings.selectedVoiceID
            selectedVoiceName = settings.selectedVoiceName
            wakeWord = settings.wakeWord.isEmpty ? "hey kuromi" : settings.wakeWord
        }

        wakeWordService.onTrainingSampleCaptured = { [weak self] text in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.trainingSamples.append(text)
                self.isRecordingTraining = false
                if self.currentTrainingStep < 3 {
                    self.currentTrainingStep += 1
                }
            }
        }
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
                    self.voices = voiceList
                    self.isLoadingVoices = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.voiceLoadError = error.localizedDescription
                    self.isLoadingVoices = false
                }
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
        settings.wakeWord = computeFinalWakeWord()
        settings.save()
    }

    private func computeFinalWakeWord() -> String {
        guard !trainingSamples.isEmpty else { return wakeWord }
        // Use the most common/similar sample or just the first one
        return trainingSamples.first ?? wakeWord
    }
}
