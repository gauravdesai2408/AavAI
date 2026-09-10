# AavAI

A native macOS push-to-talk dictation MVP with context-aware cleanup and safe text insertion.

## Run locally with no API key

Requirements: macOS 14+, Swift 6.2+, Node 22+, microphone access, and Accessibility access.

Install the local Whisper and Ollama engines once, then start the complete stack:

```sh
chmod +x scripts/*.sh
./scripts/setup-local-models.sh
./scripts/run-local.sh
```

To build and install the standalone Mac application (models included, no Terminal required after launch):

```sh
chmod +x scripts/*.sh
./scripts/install-app.sh
```

The app is installed at `~/Applications/AavAI.app`. Its signed bundle includes the local Whisper, Ollama, Qwen, Node, and backend runtime and starts them automatically.

Hold **Control + Space**, speak, and release. Audio and text remain on this Mac. Logs are written under `.runtime/` and models under `.local-models/`.

Inside AavAI, **Start dictation** opens a transcript dialog. Stop recording to
see the original and polished text, then copy it. This action does not activate
the previous external app. Click a History entry to open its full transcript.

In Settings, **Speech recognition** selects Accuracy (local Whisper
large-v3-turbo Q5) or Speed (local small.en). Switching restarts local services;
wait for “Local AI ready” before recording. Accuracy is the default and takes
longer. Our small English whisper evaluation showed improvements on clean
speech and the separate noisy validation subset, but regressions on some
sentences. It does not establish parity with Wispr Flow; see
`.evaluation/cstr/model-comparison.md` for exact scope and results.

Run all tests (including a native Swift Testing runner for Command Line Tools-only Macs):

```sh
./scripts/test-swift.sh
cd backend && npm test
```

For managed transcription and cleanup:

```sh
AAVAI_PROVIDER=openai OPENAI_API_KEY=... npm start
```

`AAVAI_BACKEND_URL` changes the client backend URL. Production deployments must add authentication, TLS, persistent metering, Stripe webhooks, signed updates, hardened runtime entitlements, and provider data-retention agreements before making privacy claims.

## Repository layout

- `Sources/AavAI`: native SwiftUI/AppKit client and stable service contracts.
- `Tests/AavAITests`: state-machine and recovery tests.
- `backend`: dependency-free HTTP gateway, provider adapters, validation, quotas, and tests.
