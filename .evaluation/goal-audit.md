# Requested experience: completion audit — 2026-09-12

## Delivered and verified

- In-app recording uses preview-only mode and shows a dedicated transcript sheet.
  Source: AppViews.swift, TranscriptViews.swift, DictationCoordinator.swift.
  Regression test verifies no external insertion for in-app dictation.
- History rows open a transcript detail sheet. Installed-app AppleScript smoke
  test opened the first history row and observed the sheet title `Transcript`.
- Recording cancellation works in the installed dialog. Delayed microphone
  startup cannot duplicate recording or revive a cancelled session: a new test
  failed on all three assertions before the patch and passes after it.
- Release build and signature verification passed. Installed executable matches
  dist byte-for-byte. Previous installation preserved as
  `/Users/gauravdesai/Applications/AavAI.before-start-race.app`.
- Installed local transcription and cleanup services reported healthy.
- Accuracy mode now performs a confidence-gated retry with the already bundled
  small.en model. Installed health reported `whisper`, `fallbackWhisper`, and
  `ollama` all true. The installed backend recovered the public “working hard”
  sample exactly. On 24 independent CSTR clean/noisy clips, errors improved from
  3/136 to 2/136; see public-whispers.md for limitations and evidence files.
- A final-output meaning guard prevents cleanup from introducing replacement
  words. It reproduced red before the fix and passed green afterward; installed
  verification preserved “while” and returned the `meaningGuard` diagnostic.
- Keychain history decryption was moved off synchronous app initialization after
  a process sample proved `SecItemCopyMatching` blocked the main thread. The
  installed window now opens immediately, local AI reports Ready, and both
  preexisting encrypted history rows load.

## Accuracy evidence and limitation

Public audio testing needs no recording from the user. Completed tests cover
CSTR headset whispers and 15 CLARIS demo inputs spanning seven speaker IDs.
See cstr/model-comparison.md and public-whispers.md for provenance and caveats.
Compared small, medium, Turbo, full large-v3, beam size 5 and bounded gain.
Meaning-changing recognition errors remain. Neither model size nor gain
provided a robust remedy; the beam improvement did not increase exact matches.
Follow-up beam-plus-fallback, pre-emphasis, temperature sampling, and local-model
candidate arbitration also failed to improve the current adaptive aggregate.
The whispered-ASR-specific PALF-LF Whisper-small model was screened out before
download because its published benchmark was slightly worse than its own plain
fine-tuned baseline and the difference was not statistically significant. No
new model or conversion dependency was installed during that screening.
One stronger-license candidate, `burakaydinofficial/whisper-small-24lang`, was
then evaluated end-to-end because it is a standard Whisper-small checkpoint
fine-tuned on CC0 whispered speech. It regressed CLARIS to 16/112 errors and the
independent CSTR gate to 9/136, including a high-confidence one-word hallucination.
It was rejected and its temporary model/conversion environment was deleted.
NVIDIA Parakeet TDT 0.6B v3 was also evaluated through the already-built local
CLI. It improved the curated CLARIS set to 7/112 errors and was substantially
faster, but regressed the independent CSTR gate to 5/136 versus production's
2/136. Because the CLI provides no calibrated confidence for safe routing, it
was not promoted; its temporary model was deleted after the benchmark.

The requirement to match Wispr Flow remains unproven. There are no same-audio
Wispr Flow outputs in the evaluation evidence. With user approval, Flow 1.6.827
and BlackHole 2ch 0.7.1 were installed; the user signed in and completed installer
consent. Flow settings confirmed English and BlackHole input. The control tool
rejects `fn` with keyNotFound; alternative shortcut capture ignored automated
Ctrl-Alt-D and F8. No test audio was submitted and no competitor score is valid.
Public AavAI benchmarks cannot establish relative accuracy by themselves.

## Test-installation cleanup

User explicitly requested removal after testing. Flow was quit and its input
restored to Auto-detect (MacBook Air). Flow.app, benchmark-only medium.en and
large-v3 model files, playback helper, and cached BlackHole installer were moved
to the user's Trash (recoverable). AavAI, its active Turbo/small models, saved
benchmark results, and the preexisting Parrot audio driver were preserved.
System profiler confirms MacBook Air microphone and speakers are still defaults.
Finder completed removal of the exact BlackHole2ch.driver. Filesystem verification
confirms it is absent from /Library/Audio/Plug-Ins/HAL and present in user Trash;
ParrotAudioPlugin.driver remains installed. CoreAudio still lists BlackHole in
the current session: a normal Mac restart is needed to clear the loaded driver.
No restart or interruption of system audio was forced.

## Next decision

2026-09-14: Apple SFSpeechRecognizer was exercised through an isolated signed
app launched with LaunchServices, with requiresOnDeviceRecognition=true and a
guard requiring local recognition support. On the 24 CSTR clips, 13 returned
empty output without an error; 11 returned text, two with word errors. Repeating
with unique output paths, synchronous stdout writes, and 16 kHz conversion did
not resolve this. `.evaluation/cstr/apple-speech.json` is diagnostic evidence,
not a valid general model accuracy score. Apple recognition was not integrated.
The temporary helper app and compiler cache were deleted after the attempt.

Do not claim parity, erase the original requirement, or repeat the same local
experiments as proof of completion. A fair competitor comparison requires
working recording controls for testing the same public recordings there.
The user does not need to record voice memos. Approval and sign-in are resolved;
do not ask for those again. Test tools were removed at the user's request.
The app remains usable with the delivered dialog/history fixes and the measured
adaptive accuracy improvement while that comparison is unavailable. Goal
completion must remain unclaimed because Wispr parity is still unverified.
