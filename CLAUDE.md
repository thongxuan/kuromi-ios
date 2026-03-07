# CLAUDE.md — Kuromi iOS

Real-time voice chat app for iOS. Supports two modes:
- **Relay mode**: streams PCM audio to a relay server; relay handles STT/gateway/TTS
- **On-device mode**: `SFSpeechRecognizer` STT + `AVSpeechSynthesizer` TTS + direct WebSocket to OpenClaw gateway

---

## Architecture (Always-On Mic)

The audio engine runs continuously while ChatView is visible. This prevents crashes caused by AVAudioEngine stop/start when AirPods connect/disconnect (HW format mismatch).

### Core Components
```
iPhone
  └── AudioEngine (singleton, always running)
       ├── Single AVAudioEngine instance
       ├── installTap on inputNode, routes buffers based on chatState
       ├── Converts native format → PCM 16kHz int16 for relay/STT
       └── State-based routing via consumers:
           ├── idle → wakeWordConsumer (native buffer)
           ├── listening → relayConsumer (PCM) + onDeviceSTTConsumer (native)
           └── aiThinking/aiSpeaking → preBufferConsumer (threshold gated)
  └── AudioSessionManager (singleton)
       ├── setupForChat(): .playAndRecord, allowBluetooth, allowBluetoothA2DP
       ├── setSpeaker(_ loud: Bool): overrideOutputAudioPort
       └── handleRouteChange: re-apply session settings (no engine restart)
```

### Relay Mode
```
iPhone
  └── AudioEngine → routes buffers to:
  └── WakeWordService.appendBuffer() — wake word detection (idle state)
  └── AudioRelayService.appendBuffer() — PCM streaming to relay (listening state)
       ├── WebSocket to relay server
       ├── receives transcript JSON events
       ├── receives TTS audio (binary WAV chunks) → AVAudioPlayer(data:)
       └── barge-in: detects RMS > 0.3 during TTS
  └── ChatViewModel
       ├── state machine: connecting → idle → listening → aiThinking → aiSpeaking
       ├── triggerStart() — called by orb tap or wake word
       ├── triggerStop() — called by orb tap or stop phrase
       └── setupAudioEngineConsumers() — wire buffer routing
```

### On-Device Mode
```
iPhone
  └── AudioEngine → routes buffers to:
  └── WakeWordService.appendBuffer() — wake word detection (idle state)
  └── OnDeviceSTTService.appendBuffer() — SFSpeechRecognizer (listening state)
       ├── silence timer (1.5s) → onFinalTranscript
       └── finalTriggered flag prevents double-fire
  └── GatewayService (WebSocket to OpenClaw gateway)
       ├── sendMessage(text) → chat.send
       ├── onDelta → streaming text chunks
       └── onResponseComplete → triggers on-device TTS
  └── OnDeviceTTSService (AVSpeechSynthesizer)
  └── ChatViewModel (same state machine)
```

---

## State Machine (ChatViewModel)

```swift
enum ChatState {
    case connecting       // Initial connection to relay/gateway
    case idle             // Wake word listening
    case listening        // User speaking, sending to relay/STT
    case aiThinking       // Waiting for AI response, pre-buffering mic
    case aiSpeaking       // TTS playing, pre-buffering with threshold gate
    case error(String)    // Error state
}
```

### State Transitions
```
.connecting → (relay ready / gateway connected) → .idle

.idle
  ├── wake word detected → triggerStart() → .listening
  ├── orb tap → triggerStart() → .listening
  └── (wake word listening via WakeWordService)

.listening
  ├── stop phrase detected → triggerStop() → .idle
  ├── orb tap → triggerStop() → .idle
  ├── relay mic_stop (silence) → .aiThinking
  └── on-device: silence timer → .aiThinking → send to gateway

.aiThinking
  ├── TTS starts → .aiSpeaking
  └── (pre-buffering mic input)

.aiSpeaking
  ├── barge-in (RMS > 0.3) → stop TTS → .listening
  ├── TTS ends → .listening (auto-continue)
  └── (pre-buffering with echo gate threshold 0.15)

.listening → orb tap → triggerStop() → .idle
```

### Orb Tap Behavior
- **idle/aiSpeaking** → `triggerStart()` — begin listening
- **listening/aiThinking** → `triggerStop()` — cancel and return to idle

---

## Screens

### SetupView
Two setting rows, each opens a bottom sheet:
- **Gateway** → URL (ws://...) + Token
- **Language** → Language picker + Wake phrase + Stop phrase
- **On-device voice** toggle (shown on A14+ devices)

### ChatView
Single screen with:
- Top bar: status dot, connection label, text toggle, speaker toggle, settings
- Orb: animated circle, tap to start/stop; reacts to voice level
  - Pulsing ring animation during aiThinking state
- Status hint: "Tap or say 'mi ơi'" (opacity only, never shifts layout)
- Reconnect button: appears below orb on disconnect
- Transcript list: toggled via text icon, shows messages + live AI streaming response

---

## Key Files

| File | Purpose |
|------|---------|
| `KuromiApp.swift` | App entry, `AppState`, `RootView` |
| `Models/AppSettings.swift` | Persisted settings: gatewayURL, token, language, wakePhrase, stopPhrase, useOnDeviceVoice |
| `Models/Message.swift` | Chat message model (user/assistant roles) |
| `Services/AudioEngine.swift` | **Singleton AVAudioEngine manager**: always-on mic, state-based buffer routing, format conversion |
| `Services/AudioSessionManager.swift` | **Centralized AVAudioSession**: setup, speaker toggle, route change handling |
| `Services/AudioRelayService.swift` | WebSocket to relay, PCM streaming via appendBuffer(), TTS playback, barge-in |
| `Services/GatewayService.swift` | Direct WebSocket to OpenClaw gateway; streaming delta/complete callbacks; auto-reconnect |
| `Services/OnDeviceSTTService.swift` | `SFSpeechRecognizer` via appendBuffer(); silence timer; finalTriggered guard |
| `Services/OnDeviceTTSService.swift` | `AVSpeechSynthesizer` TTS for on-device mode |
| `Services/WakeWordService.swift` | `SFSpeechRecognizer` wake word via appendBuffer(), locale mapping, fuzzy match |
| `ViewModels/ChatViewModel.swift` | State machine, triggerStart/triggerStop, audio engine consumers, relay + on-device callbacks |
| `ViewModels/SetupViewModel.swift` | Form state, validation, save/load |
| `Views/ChatView.swift` | Orb UI (with PulsingRingView for aiThinking), transcript list, top bar |
| `Views/SetupView.swift` | Setup form, bottom sheets, `KuromiTextField`, `SettingRow` |
| `Helpers/AppColors.swift` | Adaptive color tokens (dark/light mode via UIColor) |
| `Helpers/FuzzyMatch.swift` | Levenshtein-based fuzzy match for wake/stop phrase detection |
| `Helpers/SoundPlayer.swift` | System sound helpers (1111 start, 1110 stop); works alongside always-on engine |

---

## Audio Session Management

- **AudioSessionManager.shared**: centralized session configuration
- **Session category**: `.playAndRecord`, mode `.default`, options `[.allowBluetooth, .allowBluetoothA2DP]`
- **Speaker output**: `overrideOutputAudioPort(.speaker)` when `isLoudSpeaker = true`
- **Route change handling**: re-apply session settings, never restart engine
- **TTS playback (relay mode)**: `AVAudioPlayer(data:)` — audio data held in memory
- **TTS playback (on-device)**: `AVSpeechSynthesizer`
- **Mic capture**: `AudioEngine` singleton with continuous tap, routes to consumers
- **Barge-in**: RMS level > 0.3 during TTS → stop TTS, transition to listening
- **Echo gate**: During aiSpeaking, only buffer audio with RMS > 0.15
- **System sounds**: `1111` (start), `1110` (stop) via `AudioServicesPlaySystemSound`

---

## Wake Word & Stop Phrase

- **Wake word**: `SFSpeechRecognizer` fed from AudioEngine via appendBuffer()
- **Stop phrase**: detected in onTranscript callback (iOS side, relay unaware)
- **Fuzzy matching**: 70% Levenshtein threshold, sliding window for multi-word phrases
- **Locale mapping**: `vi→vi-VN`, `en→en-US`, `ja→ja-JP`, `zh→zh-CN`, `ko→ko-KR`, etc.
- **Resume**: wake word resumes after transition to idle

---

## On-Device STT Notes

- `requiresOnDeviceRecognition = false` — server-based STT is more reliable (avoids error 1101 when model not downloaded)
- `finalTriggered` flag: prevents `onFinalTranscript` being called twice when both silence timer and `isFinal` fire close together
- Reset `finalTriggered` in `stop()` to allow fresh session on next `start()`

---

## GatewayService (On-Device Mode)

- Connects via `URLSessionWebSocketTask` to OpenClaw gateway
- Handshake: `connect.challenge` → sends `connect` req with auth token
- Sends `chat.send` with `sessionKey`, `message`, `idempotencyKey`, `deliver: false`
- Filters events by `sessionKey` and active `runId`
- Streaming: `onDelta` fired per text chunk → `ChatViewModel` updates `currentAIResponse` live
- `onResponseComplete`: fired on `lifecycle.end` → clears `currentAIResponse`, triggers TTS
- **Auto-reconnect**: schedules reconnect after 2s on close

---

## Relay (kuromi/relay)

- **Entry**: `index.js`, port 18790
- **Start**: `bash start.sh` (auto-restart loop)
- **Tunnel**: ngrok with static domain
- **STT**: Deepgram WebSocket streaming
- **TTS**: valtec-tts local server
- **Gateway**: OpenClaw WebSocket, `deliver: false`
- **micStopped flag**: blocks Deepgram results after user stops

---

## Relay WebSocket Protocol

### iOS → Relay
```json
{ "type": "start", "language": "vi", "token": "...", "voice": "NF" }
{ "type": "stop" }
{ "type": "barge_in" }
<binary PCM int16 16kHz chunks>
```

### Relay → iOS
```json
{ "type": "ready" }
{ "type": "transcript", "text": "...", "is_final": true }
{ "type": "mic_stop" }
{ "type": "ai_text", "text": "..." }
{ "type": "tts_start" }
<binary WAV chunks>
{ "type": "tts_end" }
{ "type": "tts_abort" }
```

---

## Environment / Config

Relay `.env`:
```
OPENCLAW_WS=ws://localhost:18790
OPENCLAW_TOKEN=...
DEEPGRAM_API_KEY=...
SILENCE_TIMEOUT_MS=1500
```
