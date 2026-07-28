# LFM2.5-Audio integration

## Decision

Nyoy owns the lifecycle, connection configuration, health check, and tool-facing
contract for `LFM2.5-Audio-1.5B-JP`. KBMemo owns microphone and playback UI.
The two applications do not load or configure the audio model independently.

`LFM2.5-Audio-1.5B-JP` is an audio/text model with ASR, TTS, and interleaved
audio generation. It requires its audio encoder and output decoder/vocoder;
it is not a text-only `llama-server` profile and must not be managed as a
llama-switchd server binding.

## Boundaries

| Component | Responsibility |
| --- | --- |
| `lfm-audio-service` | Python `liquid-audio` runtime, model loading, waveform decoding/encoding, ASR/TTS. |
| Nyoy `ServiceConnection(lfm_audio)` | URL, auth token, enabled state, health and operational diagnostics. |
| Nyoy audio adapter | Request limits, MIME validation, upstream errors, and an application-stable API contract. |
| Nyoy MCP / authenticated HTTP facade | Authorizes callers and exposes transcription/synthesis without exposing the runtime directly. |
| KBMemo | Records audio, submits it to Nyoy, places transcription text in the existing chat input, and plays returned audio. |

The initial implementation remains text-first: an utterance is transcribed before
the existing Agent flow runs, and only the final assistant answer can be
synthesized. This preserves tool calls, RAG, message history, cancellation, and
audit behavior.

## Service contract

`lfm-audio-service` is private to the host or private network and requires a
service token. Its adapter-facing API is deliberately compatible with the common
OpenAI audio surface:

```text
GET  /health
POST /v1/audio/transcriptions
POST /v1/audio/speech
```

`/v1/audio/transcriptions` receives multipart `file`, `model`, `language`, and
an optional `prompt`, returning `{ "text": "..." }`. `/v1/audio/speech` receives
JSON `model`, `input`, `voice`, and `response_format`, returning `audio/wav`.

Initial limits are 10 MiB / 120 seconds for transcription and 4,000 characters
for synthesis. Supported input formats are WebM, Ogg, WAV, and MP4. Audio payloads
and authorization headers must never be written to application logs.

## Configuration model

Add a generic `ServiceConnection` with seed key `lfm_audio`. It is not a model
endpoint and is excluded from `ServiceConnection.model_endpoints`,
`LlmUsageAssignment`, llama-switchd inventory, and model lifecycle operations.

Audio usage is a separate configuration contract:

| Usage | Selected values |
| --- | --- |
| `audio.transcription` | `ServiceConnection`, model, language, timeout |
| `audio.speech` | `ServiceConnection`, model, voice, response format, timeout |

The first release uses one enabled connection and configuration from credentials
or environment. A database-backed audio usage administration screen is deferred
until the service has passed real-host verification.

Initial environment names:

```sh
LFM_AUDIO_URL=http://127.0.0.1:10120
LFM_AUDIO_TOKEN=...
LFM_AUDIO_TRANSCRIPTION_MODEL=LiquidAI/LFM2.5-Audio-1.5B-JP
LFM_AUDIO_SPEECH_MODEL=LiquidAI/LFM2.5-Audio-1.5B-JP
LFM_AUDIO_SPEECH_VOICE=default
```

## Delivery phases

1. Build and operate `lfm-audio-service` as a separate systemd user service on
   bowmore. Verify health, a Japanese ASR sample, a Japanese TTS sample, startup
   memory, and latency on CPU before application integration.
2. Add Nyoy `lfm_audio` connection, adapter, authenticated audio facade, and
   MCP tools. Add request-size, MIME, auth, cancellation, and error tests.
3. Add KBMemo microphone controls to AI Chat and Memo Assist. Transcription
   fills the existing text input and requires normal user send confirmation.
4. Add final-answer playback and stop controls. Do not synthesize streamed
   chunks, thinking, tool progress, or user messages.
5. Evaluate LFM interleaved audio-to-audio mode only after the text-first flow
   is reliable.

## Operations

The runtime is a separate user service, not restarted by Nyoy or KBMemo deploys.
The runbook must cover model files, model warmup, service token, `/health`, curl
ASR/TTS checks, CPU memory, journal inspection, restart, and rollback. Monitor
process liveness, health, synthetic ASR/TTS checks, latency, and host memory.
