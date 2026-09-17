# Native migration — implementation ledger

The baseline remains the default. No model has passed competitive promotion.
The installed application and existing `dist/AavAI.app` are not replaced by the
native-preview build. Do not run both applications concurrently: they deliberately
share the original history, dictionary, and local application identity.

## Implemented first slice

- `AavAICore` library with unchanged Codable transcript/context models.
- Mono PCM frame validation, bounded audio window, recognition-event contract,
  session identity and provisional/final insertion gate.
- Conservative whitespace-only formatting; no hallucinated correction or deletion.
- Apple SpeechTranscriber file adapter using SpeechAnalyzer, runtime availability,
  explicit system asset installation, dictionary context and cancellation.
- Opt-in Mac native path preserves the existing capture, dialog, history and
  insertion workflow; it does not start Node, Ollama or whisper.cpp servers.
- Separate native-preview packaging, without model weights/server runtimes.
- File evaluation CLI. It is not a microphone latency or quality benchmark.
- Versioned corpus and paired-output validation with WER and speaker/whisper
  breakdowns; missing or unreviewed data cannot produce a promotion result.

## Run

`scripts/test-swift.sh`

`AAVAI_BUILD_FLAVOR=native-apple scripts/build-app.sh`

Open `dist/AavAI-Native.app` after quitting the baseline. The menu's **Download
Apple English Speech Assets…** action explicitly downloads system-managed assets.
Recognition refuses to download missing assets or use cloud recognition. The
baseline remains available on macOS 14/15; this experimental engine requires 26.

For development, `AAVAI_ENGINE=apple` selects the same path in the executable.
The `aavai-native-eval` executable accepts `status`, `install-assets`, or
`transcribe /absolute/path.wav`. Its JSON deliberately contains the requested
transcript; keep evaluation output private and do not send it to analytics.

## Preservation and rollback

No saved history, Keychain service, preferences or dictionary schema is changed.
Use the original application to roll back. Keep the baseline dependencies until
the frozen evaluation gates pass. Native captured WAV files use a private temporary
directory and are removed on normal success/failure/cancellation. Crash-time
temporary-file cleanup is not yet implemented; do not claim zero disk retention.
The Apple file adapter releases its analyzer each session rather than retaining a
warm model for 60 seconds. System asset retention is controlled by macOS, not the
application; system asset deletion is not implemented.

## Outstanding gates (not implemented or not verified)

- Live PCM capture/incremental recognition, overlap reconciliation, preroll.
- WhisperKit pinning, license review, verified resumable model downloads.
- Native memory-pressure/idle policy and Foundation Models evaluation.
- Xcode/iOS SDK installation, iPhone app and physical-device testing.
- Keyboard/shared-container feasibility and entitlement verification.
- 300 licensed/consented recordings, 12 speakers, frozen speaker-disjoint split.
- Paired Flow output, blinded correction review, uncertainty, resource profiling.
- 500 insertion attempts, 20-minute phone thermal run and offline network audit.

Only Command Line Tools were found during readiness checks; full Xcode is absent.
The out-of-sandbox native status probe returned `assets-not-installed` for English.
The preview bundle measured approximately 1.5 MB, excluding system speech assets
and runtime RAM. This is packaging evidence only, not a footprint/quality pass.
Do not equate a compiled Mac adapter with functioning or validated iPhone support.
No paid dependencies are added. No test-only software or model was installed in
this implementation slice.
