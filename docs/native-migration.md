# Native migration — implementation ledger

The baseline remains the default. No model has passed competitive promotion.
Current delivery scope is Mac only (user decision, 2026-09-19). iPhone, keyboard
extensions, provisioning and phone thermal tests are deferred, not prerequisites
for this Mac milestone. Do not install Xcode solely for the deferred phone work.
Keep one installed app. Old backup apps and redundant dist outputs were moved to
Trash at the user's request. Do not recreate them without a concrete test need and
cleanup plan. Source changes below are not deployed merely by running tests.

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
`transcribe /absolute/path.wav` or `transcribe-memory /absolute/path.wav`.
The latter exercises the Mac app's bounded in-memory PCM/resampling path (PCM16
WAV, up to 120 seconds), not merely Apple's file-input API. Results identify the
input path so the two routes are not silently mixed in comparisons. Neither
command downloads missing assets. Its JSON deliberately contains the requested
transcript; keep evaluation output private and do not send it to analytics.

## Preservation and rollback

History's encrypted format and Keychain identity remain unchanged. Dictionary
terms now migrate to AES-GCM encrypted preferences with a separate Keychain key;
the old plaintext preference is removed only after successful encryption. Older
installed binaries cannot read this new dictionary format. Export terms before
rolling back to an older binary; do not silently reintroduce plaintext storage.
Keep baseline dependencies until the frozen evaluation gates pass.
Native microphone transcription consumes validated in-memory WAV data and
one-second resampled chunks; it no longer creates temporary capture files. This
does not remove historical crash remnants or imply secure RAM erasure. The CLI
file adapter reads supplied recordings and does not delete them.
The Apple file adapter releases its analyzer each session rather than retaining a
warm model for 60 seconds. System asset retention is controlled by macOS, not the
application; system asset deletion is not implemented.

## Privacy implementation pass (2026-09-18)

- Failed history loads do not overwrite existing bytes. Writes/deletions commit
  in-memory changes only after persistence succeeds; the UI exposes failures.
- History saving is opt-in; existing records remain. Retention requires confirmation
  before deleting old records. Checks run on load/save/export and every minute
  while the root view is active, not as an always-running background service.
- Local JSON export is explicit and unencrypted, with a cloud-folder warning.
- Context is off by default; opt-in capture requests a bounded range near the cursor.
  Unsupported fields provide none instead of reading the whole field.
- Insertion rechecks the focused element and secure status. Automatic clipboard
  fallback can be disabled; explicit Copy still uses the system clipboard.
- Capture is limited to 120 seconds; buffers are released on stop/cancel. Only
  digital-zero PCM is rejected by the capture silence check.
- Desktop and baseline inference endpoints are loopback-only and reject redirects.
  Cloud provider code is removed. Parser/provider error text is not logged or echoed.
- Dictionary preference durability, UI/device behavior, network audit, update
  security and legal/operational readiness still require verification.

## Remaining gates

- EU privacy/security readiness: see [EU requirements and release blockers](eu-readiness.md).

- Live PCM capture/incremental recognition, overlap reconciliation, preroll.
- WhisperKit pinning, license review, verified resumable model downloads.
- Native memory-pressure/idle policy and Foundation Models evaluation.
- 300 licensed/consented recordings, 12 speakers, frozen speaker-disjoint split.
- Paired Flow output, blinded correction review, uncertainty, resource profiling.
- 500 Mac insertion attempts and offline network audit.

Deferred: iPhone app/device testing, keyboard/shared-container entitlements and
20-minute phone thermal run. Reopen these only when mobile work resumes.

Only Command Line Tools were found during readiness checks; full Xcode is absent.
The out-of-sandbox native status probe returned `assets-not-installed` for English.
The preview bundle measured approximately 1.5 MB, excluding system speech assets
and runtime RAM. This is packaging evidence only, not a footprint/quality pass.
Do not equate a compiled Mac adapter with functioning or validated iPhone support.
No paid dependencies are added. No test-only software or model was installed in
this implementation slice.
