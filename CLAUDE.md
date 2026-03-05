# CLAUDE.md — OpenVoice iOS

Real-time voice chat app for iOS. Streams PCM audio to a relay server, receives TTS audio back. Wake word detection on-device. All AI/STT/TTS logic lives in the relay — the iOS app is intentionally thin.

---

## Architecture

```
iPhone
  └── WakeWordService (SFSpeechRecognizer, on-device)
       └── detects wake phrase → startChat()
  └── AudioRelayService (WebSocket + AVAudioEngine)
       ├── streams raw PCM 16kHz int16 to relay
       ├── receives transcript JSON events
       ├── receives TTS audio (binary WAV chunks)
       └── barge-in: sends barge_in when mic level > 0.2 during TTS
  └── ChatViewModel
       ├── state machine: idle → userSpeaking → aiSpeaking → idle
       ├── startChat(beep:) — called by orb tap or wake word
       ├── stopChat() — called by orb tap or stop phrase detection
       └── finalizeStop(fromMicStop/fromTTSEnd/timeout) — resume wake word
```

```
Relay (Node.js, port 18790)
  ├── receives PCM binary → streams to Deepgram STT
  ├── silence timer (SILENCE_TIMEOUT_MS=1500) → sends transcript + mic_stop
  ├── sends transcript text to OpenClaw gateway (chat.send)
  ├── gateway agent response → valtec-tts → TTS audio → streams to iOS
  └── micStopped flag: blocks Deepgram results after iOS sends stop
```

---

## Screens

### SetupView
Two setting rows, each opens a bottom sheet:
- **Gateway** → URL (ws://...) + Token
- **Language** → Language picker + Wake phrase + Stop phrase

### ChatView
Single screen with:
- Top bar: status dot, connection label, text toggle, settings
- Orb: animated circle, tap to start/stop
- Status hint: "Tap or say 'mi ơi'" (opacity only, never shifts layout)
- Reconnect button: appears below orb on disconnect
- Transcript list: toggled via text icon, slides from top

---

## Key Files

| File | Purpose |
|------|---------|
| `KuromiApp.swift` | App entry, `AppState`, `RootView` |
| `Models/AppSettings.swift` | Persisted settings: gatewayURL, token, language, wakePhrase, stopPhrase |
| `Models/Message.swift` | Chat message model (user/ai roles) |
| `Services/AudioRelayService.swift` | WebSocket client, mic capture, PCM streaming, TTS playback, barge-in |
| `Services/WakeWordService.swift` | `SFSpeechRecognizer` wake word loop, locale mapping, fuzzy match |
| `Services/GatewayService.swift` | (legacy, unused — relay handles gateway now) |
| `ViewModels/ChatViewModel.swift` | State machine, startChat/stopChat/finalizeStop, callbacks |
| `ViewModels/SetupViewModel.swift` | Form state, validation, save/load |
| `Views/ChatView.swift` | Orb UI, transcript list, top bar |
| `Views/SetupView.swift` | Setup form, bottom sheets, `KuromiTextField`, `SettingRow` |
| `Helpers/AppColors.swift` | Adaptive color tokens (dark/light mode via UIColor) |
| `Helpers/FuzzyMatch.swift` | Levenshtein-based fuzzy match for wake/stop phrase detection |

---

## State Machine (ChatViewModel)

```
.idle
  ├── wake word detected → startChat(beep: true)
  ├── orb tap → startChat(beep: true)
  └── (wake word listening via WakeWordService)

.userSpeaking
  ├── stop phrase detected in transcript → stopChat()
  ├── orb tap → stopChat()
  └── relay sends mic_stop (silence timeout) → onMicStop → .idle

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
  → play sound 1114
  → stopMic() after 150ms

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

## Audio

- **Mic capture**: `AVAudioEngine`, native format → convert to PCM 16kHz int16
- **TTS playback**: buffered WAV from relay, `AVAudioPlayer`
- **Audio session**: `.playAndRecord` `.default` mode during playback; relay's `micStopped` flag prevents echo transcripts
- **Barge-in**: RMS level > 0.2 during TTS → send `barge_in` to relay (once per TTS, `didBargeIn` flag)
- **System sounds**: `1113` begin_record (start), `1114` end_record (stop)

---

## Wake Word & Stop Phrase

- **Wake word**: `SFSpeechRecognizer` continuous recognition loop
- **Stop phrase**: detected in `onTranscript` callback (iOS side only, relay unaware)
- **Fuzzy matching**: 70% Levenshtein threshold, sliding window for multi-word phrases
- **Locale mapping**: `vi→vi-VN`, `en→en-US`, `ja→ja-JP`, `zh→zh-CN`, `ko→ko-KR`, etc.
- **Resume**: wake word only resumes AFTER final TTS ends (not on mic_stop)

---

## Relay (kuromi/relay)

- **Entry**: `index.js`, port 18790
- **Start**: `bash start.sh` (auto-restart loop, lock at `/tmp/kuromi-relay.lock`)
- **Tunnel**: ngrok with static domain `ta-unsmooth-crispily.ngrok-free.dev`
- **STT**: Deepgram WebSocket streaming
- **TTS**: valtec-tts local server (Vietnamese NF voice, ~0.65s GPU)
- **Gateway**: OpenClaw WebSocket, `agent:main:main` session, `deliver: false`
- **activeReqIds**: tracks reqId→runId to filter agent events (prevents duplicate TTS from Telegram)
- **micStopped flag**: set on `stop` message, cleared on `start` — blocks Deepgram results after user stops

---

## Relay WebSocket Protocol

### iOS → Relay
```json
{ "type": "start", "language": "vi", "token": "...", "voice": "nova" }
{ "type": "stop" }
{ "type": "barge_in" }
<binary PCM int16 16kHz chunks>
```

### Relay → iOS
```json
{ "type": "transcript", "text": "...", "is_final": true }
{ "type": "mic_stop" }
{ "type": "ai_text", "text": "..." }
{ "type": "tts_start" }
<binary WAV chunks>
{ "type": "tts_end" }
{ "type": "tts_abort" }
{ "type": "audio_level", "level": 0.5 }
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

---

## Tags

- `rc1` — `kuromi-ios@e0573c1`, `kuromi-relay@f1966d7`
- `rc1.1` — `kuromi-ios@9e2367a`
