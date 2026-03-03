import Foundation

// MARK: - STT Providers
enum STTProvider: String, CaseIterable, Codable {
    case deepgram = "deepgram"
    case openaiWhisper = "openai_whisper"

    var displayName: String {
        switch self {
        case .deepgram: return "Deepgram"
        case .openaiWhisper: return "OpenAI Whisper"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepgram: return "nova-2"
        case .openaiWhisper: return "whisper-1"
        }
    }

    var availableModels: [String] {
        switch self {
        case .deepgram: return ["nova-2", "nova-2-general", "nova-2-meeting", "nova-2-phonecall", "base", "enhanced"]
        case .openaiWhisper: return ["whisper-1"]
        }
    }
}

// MARK: - TTS Providers
enum TTSProvider: String, CaseIterable, Codable {
    case openai = "openai"
    case elevenlabs = "elevenlabs"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI TTS"
        case .elevenlabs: return "ElevenLabs"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "tts-1"
        case .elevenlabs: return "eleven_multilingual_v2"
        }
    }

    var availableModels: [String] {
        switch self {
        case .openai: return ["tts-1", "tts-1-hd"]
        case .elevenlabs: return ["eleven_multilingual_v2", "eleven_turbo_v2", "eleven_monolingual_v1"]
        }
    }
}

// MARK: - Provider Config
struct ProviderConfig: Codable {
    var apiKey: String = ""
    var model: String = ""
}
