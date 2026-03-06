# CLAUDE.md — Kuromi iOS

Real-time voice chat app for iOS. Supports two modes:
- **Relay mode**: streams PCM audio to a relay server; relay handles STT/gateway/TTS
- **On-device mode**: `SFSpeechRecognizer` STT + `AVSpeechSynthesizer` TTS + direct WebSocket to OpenClaw gateway

---

## Architecture

### Relay Mode
```
iPhone
  └── WakeWordService (SFSpeechRecognizer, on-device, continuous)
       └── detects wake phrase → startChat()
  └── AudioRelayService (WebSocket + AVAudioEngine)
       ├── streams raw PCM 16kHz int16 to relay
       ├── receives transcript JSON events
       ├── receives TTS audio (binary WAV chunks) → AVAudioPlayer(data:)
       └── barge-in: sends barge_in when mic RMS level > 0.2 during TTS
  └── ChatViewModel
       ├── state machine: connecting → idle → userSpeaking → aiSpeaking → idle
       ├── startChat(beep:) — called by orb tap or wake word
       ├── stopChat() — called by orb tap or stop phrase detection
       └── finalizeStop(fromMicStop/fromTTSEnd/timeout) — resume wake word
```

### On-Device Mode
```
iPhone
  └── WakeWordService (SFSpeechRecognizer, on-device, continuous)
  └── OnDeviceSTTService (SFSpeechRecognizer)
       ├── silence timer (1.5s) → onFinalTranscript
       └── finalTriggered flag prevents double-fire (silence timer + isFinal race)
  └── GatewayService (WebSocket to OpenClaw gateway)
       ├── sendMessage(text) → chat.send
       ├── onDelta → streaming text chunks (updates currentAIResponse live)
       ├── onResponseComplete → triggers on-device TTS
       └── auto-reconnect: 2s after WebSocket close
  └── OnDeviceTTSService (AVSpeechSynthesizer)
  └── ChatViewModel (same state machine)
```

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
| `Services/AudioRelayService.swift` | WebSocket client, mic capture, PCM streaming, TTS playback (in-memory, no temp files), barge-in |
| `Services/GatewayService.swift` | Direct WebSocket to OpenClaw gateway; streaming delta/complete callbacks; auto-reconnect on close |
| `Services/OnDeviceSTTService.swift` | `SFSpeechRecognizer` for on-device STT; silence timer; double-fire guard (`finalTriggered`) |
| `Services/OnDeviceTTSService.swift` | `AVSpeechSynthesizer` TTS for on-device mode |
| `Services/WakeWordService.swift` | `SFSpeechRecognizer` wake word loop, locale mapping, fuzzy match |
| `ViewModels/ChatViewModel.swift` | State machine, startChat/stopChat/finalizeStop, relay + on-device callbacks |
| `ViewModels/SetupViewModel.swift` | Form state, validation, save/load |
| `Views/ChatView.swift` | Orb UI, transcript list (with live AI streaming preview), top bar |
| `Views/SetupView.swift` | Setup form, bottom sheets, `KuromiTextField`, `SettingRow` |
| `Helpers/AppColors.swift` | Adaptive color tokens (dark/light mode via UIColor) |
| `Helpers/FuzzyMatch.swift` | Levenshtein-based fuzzy match for wake/stop phrase detection |
| `Helpers/SoundPlayer.swift` | System sound helpers (1111 start, 1110 stop); completion always on main thread |

---

## State Machine (ChatViewModel)

```
.connecting → (relay ready / gateway connected) → .idle

.idle
  ├── wake word detected → startChat(beep: true)
  ├── orb tap → startChat(beep: true)
  └── (wake word listening via WakeWordService)

.userSpeaking
  ├── stop phrase detected in transcript → stopChat()
  ├── orb tap → stopChat()
  ├── relay sends mic_stop (silence timeout) → onMicStop → .idle
  └── on-device: silence timer fires → onFinalTranscript → send to gateway

.aiSpeaking
  ├── TTS ends → onTTSEnd → .idle (or finalizeStop if isStopping)
  └── barge-in: user speaks loudly → relay aborts TTS

.idle (after stop)
  └── finalizeStop() → resumeWakeWord() after 500ms delay
```

### Stop Flow Detail
```
stopChat()
  → isStopping = true
  → play sound 1110
  → stopMic() / onDeviceSTTService.stop()

onMicStop (isStopping=true)
  → finalizeStop(fromMicStop: true)
  → ignoreNextTTSEnd = true, pendingWakeWordResume = true
  → 5s timeout started

onTTSEnd (ignoreNextTTSEnd=true)     ← final TTS played after stop
  → chatState = .idle
  → cancel 5s timer
  → resumeWakeWord() after 500ms     ← wake word resumes HERE

5s timeout (if no TTS arrived)
  → finalizeStop() → resumeWakeWord()
```

---

## Audio Session Management

- **Session category**: `.playAndRecord`, mode `.default`, options `[.allowBluetooth, .allowBluetoothA2DP]`
- **Speaker output**: `overrideOutputAudioPort(.speaker)` when `isLoudSpeaker = true`
- **TTS playback (relay mode)**: `AVAudioPlayer(data:)` — audio data held in memory, no temp files written to disk
- **TTS playback (on-device)**: `AVSpeechSynthesizer`
- **Mic capture**: `AVAudioEngine`, native device format → convert to PCM 16kHz int16
- **Barge-in**: RMS level > 0.2 during TTS → send `barge_in` to relay (once per TTS, `didBargeIn` flag)
- **System sounds**: `1111` (start), `1110` (stop) via `AudioServicesPlaySystemSound`

---

## Wake Word & Stop Phrase

- **Wake word**: `SFSpeechRecognizer` continuous recognition loop
- **Stop phrase**: detected in `onTranscript` callback (iOS side, relay unaware)
- **Fuzzy matching**: 70% Levenshtein threshold, sliding window for multi-word phrases
- **Locale mapping**: `vi→vi-VN`, `en→en-US`, `ja→ja-JP`, `zh→zh-CN`, `ko→ko-KR`, etc.
- **Resume**: wake word only resumes AFTER final TTS ends (not on mic_stop)

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
- **Auto-reconnect**: `urlSession(_:webSocketTask:didCloseWith:reason:)` schedules reconnect after 2s

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
