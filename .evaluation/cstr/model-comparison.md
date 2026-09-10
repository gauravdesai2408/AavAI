# English whisper model comparison — in progress

Corpus attribution and license: see SOURCE.md. All recordings here are real
whispers from one speaker through a headset, in background cafeteria noise.
Models use whisper.cpp CPU execution. References are never supplied to ASR.

| Model | Development 001–012 | Separate validation 101–112 |
| --- | --- | --- |
| small.en (installed baseline) | 12 / 74 word edits, 16.22% | 40 / 88 word edits, 45.45% |
| medium.en-q5_0 | 13 / 74 word edits, 17.57% | Not run |
| large-v3-turbo-q5_0 | 17 / 74 word edits, 22.97% | 15 / 88 word edits, 17.05% |

Clean headset whispers, HERALD-CLEAN 001–006 (separate text):
- small.en: 5 / 86 edits, 5.81% literal WER.
- turbo: 1 / 86 edits, 1.16% literal WER.
- Two small.en edits were numeric formatting differences. Turbo's remaining
  error omitted “train” from “train station”. Raw outputs: small-clean.json and
  turbo-clean.json.

After silent-PCM rejection, all six normal/attenuated/silence checks passed
through LocalProvider with the turbo engine. Silence was rejected in 2 ms.

Turbo validation results are preserved in `turbo-holdout.json`, including
references, predictions, timing and per-utterance edit counts. It took roughly
3.0–3.3 seconds per recording. The small model took roughly 0.6–0.8 seconds.

The medium candidate was not promoted: it worsened development-set accuracy
and latency. Turbo reduces errors substantially on the separate validation set,
but does not establish parity with Wispr Flow. Turbo was subsequently bundled
as Accuracy mode after the separate clean and silence checks described here.
Broader speaker coverage and ordinary-speech evaluation remain necessary.

Turbo preserved all words in five normal/attenuated JFK checks, but hallucinated
“Thank you.” for digital silence. The local provider now rejects exact silent
PCM16 WAV input before inference. A regression test proves this also allows
nonzero samples through; no broad low-volume rejection was added.

Literal token scoring counts numeric formatting differences such as “100”
versus “a hundred” as edits; these percentages are not semantic failure rates.

## Expanded public-sample evaluation — 2026-09-10

Fresh run of the bundled large-v3-turbo-q5_0 model through whisper-server,
CPU-only, English, temperature 0. Twenty-four evenly spaced headset recordings
from each full HERALD directory, selected before inspecting model output.
The same sentence IDs were tested in clean and cafeteria-noise conditions.
This is broader corpus coverage, not a new speaker or a competitor comparison.

| Condition | Recordings | Word edits / reference words | Literal WER |
| --- | ---: | ---: | ---: |
| Clean whispers | 24 | 1 / 152 | 0.66% |
| Noisy whispers | 24 | 6 / 152 | 3.95% |
| Combined | 48 | 7 / 304 | 2.30% |

All 48 requests succeeded. Raw evidence: `turbo-expanded.json`.
Remaining errors include poll/pole, you/he, Scotland/Scott then, and
but/I bet. These should not be corrected with transcript-specific hardcoding.
This tests raw ASR, not microphone capture, normalization, cleanup, insertion,
or end-to-end latency. Model calls took approximately 2.7–3.3 seconds.
The corpus uses a single speaker and headset in controlled conditions; it
does not establish performance for arbitrary voices or Mac built-in microphones.

Fresh regression checks: `./scripts/test-swift.sh` passed 9 tests; backend
`npm test` passed 12 tests with localhost access. The Swift suite includes
in-app preview avoiding external insertion, cancellation and secure-field safety.
