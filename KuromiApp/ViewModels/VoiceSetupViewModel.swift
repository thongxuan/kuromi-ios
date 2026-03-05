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
}

// OpenAI voices với labels để filter
struct OpenAIVoiceOption {
    let id: String           // tên voice: nova, shimmer...
    let name: String
    let gender: VoiceGender
    let age: VoiceAge
    let tone: VoiceTone
    let descriptives: [String]
}

class VoiceSetupViewModel: ObservableObject {
    // Filters
    @Published var filterGender: VoiceGender = .female
    @Published var filterAge: VoiceAge = .young
    @Published var filterTone: VoiceTone = .high
    @Published var filterDescription: String = ""
    @Published var selectedLanguage: STTLanguage = STTLanguage.popular[0]

    // Matched voices
    @Published var matchedVoices: [OpenAIVoiceOption] = []
    @Published var selectedVoiceID: String = "nova"
    @Published var selectedVoiceName: String = "Nova"

    @Published var wakeWord: String = "hey kuromi"
    @Published var trainingSamples: [String] = []
    @Published var currentTrainingStep: Int = 0
    @Published var isRecordingTraining: Bool = false
    @Published var trainingError: String = ""

    private var openAITTSService: OpenAITTSService?

    private var cancellables = Set<AnyCancellable>()

    // Danh sách 9 voices OpenAI với labels
    static let allVoices: [OpenAIVoiceOption] = [
        OpenAIVoiceOption(id: "nova",    name: "Nova",    gender: .female, age: .young,      tone: .high, descriptives: ["warm","energetic","friendly","natural"]),
        OpenAIVoiceOption(id: "coral",   name: "Coral",   gender: .female, age: .young,      tone: .high, descriptives: ["expressive","bright","cheerful","dynamic"]),
        OpenAIVoiceOption(id: "shimmer", name: "Shimmer", gender: .female, age: .middleAged, tone: .low,  descriptives: ["calm","warm","soothing","gentle"]),
        OpenAIVoiceOption(id: "alloy",   name: "Alloy",   gender: .female, age: .young,      tone: .low,  descriptives: ["neutral","professional","clear","balanced"]),
        OpenAIVoiceOption(id: "echo",    name: "Echo",    gender: .male,   age: .young,      tone: .high, descriptives: ["warm","resonant","engaging","natural"]),
        OpenAIVoiceOption(id: "fable",   name: "Fable",   gender: .male,   age: .young,      tone: .high, descriptives: ["expressive","dynamic","storytelling","vibrant"]),
        OpenAIVoiceOption(id: "ash",     name: "Ash",     gender: .male,   age: .young,      tone: .low,  descriptives: ["confident","clear","neutral","direct"]),
        OpenAIVoiceOption(id: "onyx",    name: "Onyx",    gender: .male,   age: .middleAged, tone: .low,  descriptives: ["deep","professional","authoritative","resonant"]),
        OpenAIVoiceOption(id: "sage",    name: "Sage",    gender: .male,   age: .middleAged, tone: .low,  descriptives: ["calm","professional","measured","wise"]),
    ]

    init() {
        if let settings = AppSettings.load() {
            selectedVoiceID = settings.ttsVoice.isEmpty ? "nova" : settings.ttsVoice
            selectedVoiceName = Self.allVoices.first { $0.id == selectedVoiceID }?.name ?? "Nova"
            wakeWord = settings.wakeWord.isEmpty ? "hey kuromi" : settings.wakeWord
            selectedLanguage = STTLanguage.from(code: settings.sttLanguage)
        }


        Publishers.CombineLatest4($filterGender, $filterAge, $filterTone, $filterDescription)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyFilters() }
            .store(in: &cancellables)

        applyFilters()
    }

    func setupOpenAI(apiKey: String) {
        openAITTSService = OpenAITTSService(apiKey: apiKey)
    }

    func applyFilters() {
        let desc = filterDescription.lowercased().trimmingCharacters(in: .whitespaces)

        var scored: [(OpenAIVoiceOption, Int)] = Self.allVoices.map { voice in
            var score = 0
            if voice.gender == filterGender { score += 3 }
            if voice.age == filterAge { score += 3 }
            if voice.tone == filterTone { score += 2 }
            if !desc.isEmpty {
                let keywords = desc.split(separator: " ").map(String.init)
                for kw in keywords {
                    if voice.descriptives.contains(where: { $0.contains(kw) }) ||
                       voice.name.lowercased().contains(kw) { score += 2 }
                }
            }
            return (voice, score)
        }

        scored.sort { $0.1 > $1.1 }
        matchedVoices = scored.prefix(5).map { $0.0 }

        if !matchedVoices.isEmpty {
            let ids = matchedVoices.map { $0.id }
            if selectedVoiceID.isEmpty || !ids.contains(selectedVoiceID) {
                selectVoice(matchedVoices[0])
            }
        }
    }

    func selectVoice(_ voice: OpenAIVoiceOption) {
        selectedVoiceID = voice.id
        selectedVoiceName = voice.name
    }

    func previewVoice(_ voice: OpenAIVoiceOption) {
        openAITTSService?.speak(text: "Xin chào, em là \(voice.name), giọng đọc OpenAI!", voice: voice.id)
    }

    // MARK: - Wake Word (no training needed — relay uses Levenshtein match)

    func resetTraining() {
        trainingSamples = []
        currentTrainingStep = 0
        isRecordingTraining = false
    }

    var isTrainingComplete: Bool { currentTrainingStep >= 3 }

    func save() {
        guard var settings = AppSettings.load() else { return }
        settings.ttsVoice = selectedVoiceID
        settings.selectedVoiceName = selectedVoiceName
        settings.sttLanguage = selectedLanguage.code
        settings.wakeWord = wakeWord
        settings.save()
    }
}
