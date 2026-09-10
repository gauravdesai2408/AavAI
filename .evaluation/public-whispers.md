# Public multi-speaker whisper smoke test — 2026-09-10

Source: [CLARIS research demo](https://claris-w2s.github.io/CLARIS/),
Neil Shah, Yash Sonkar, Shirish Karande, Vineet Gandhi, CHI 2026.
Metadata: https://claris-w2s.github.io/CLARIS/scripts.js

Tested all 15 original English whisper inputs displayed by the demo across
seven speaker IDs. Excluded generated speech, Hindi, and dysarthric recordings.
These are author-selected demo clips, not an unbiased or held-out benchmark.
The source's seen/unseen labels refer to CLARIS training, not Whisper training.
Original audio was temporarily downloaded for local evaluation and removed
after the run. No audio or research model is bundled in AavAI. The full wTIMIT
dataset requires requesting access from its author; this test does not claim
a license to redistribute it or use it for training.

## Raw ASR baseline

- Bundled large-v3-turbo-q5_0 model, whisper.cpp CPU, English, temperature 0.
- 15 successful requests; 112 reference words; 13 literal word edits: 11.61% WER.
- Four edits arise from a contraction and US/UK spelling differences. These
  remain in the raw score; it is not a semantic error percentage.
- Other errors change meaning, including a verb phrase and pronouns.
- Request times approximately 2.7–2.9 seconds, excluding download/conversion.
- Evidence: `public-whispers-turbo.json`.
- Reproduce with `AAVAI_EVAL_OUTPUT=<new-path.json> node scripts/evaluate-public-whispers.mjs`
  while a temporary whisper-server is listening on localhost:8082.

This result contradicts generalizing the 2.30% one-speaker CSTR score to all
voices. Next: compare another existing model/configuration on identical inputs,
then cross-check any improvement against CSTR and silence tests. Do not hardcode
reference phrases or supply them as model prompts.

## Same-input model comparison

All three existing local models were evaluated with the same script, language,
temperature and 15 original audio URLs. No reference text was sent to ASR.

| Model | Word edits / 112 | Literal WER | Median ASR request |
| --- | ---: | ---: | ---: |
| small.en | 14 | 12.50% | 621 ms |
| medium.en-q5_0 | 12 | 10.71% | 1693 ms |
| large-v3-turbo-q5_0 | 13 | 11.61% | 2748 ms |

Evidence: `public-whispers-small.json`, `public-whispers-medium.json`, and
`public-whispers-turbo.json`. All requests succeeded. Medium corrected some
phrases but degraded another; its one-edit aggregate advantage is too small
to justify replacing Accuracy mode, especially given the earlier CSTR
development regression. Small remains a useful explicit speed tradeoff.
No installed app settings or model defaults were changed by these runs.
Temporary model servers were stopped after testing.

The principal remaining mechanism to investigate is decoding of weak acoustic
evidence, not transcript-specific cleanup replacements. Compare decoding
settings or a stronger model on a predeclared set, then validate on new clips.

## Dataset access notes

- [WSPIRE](https://spire.ee.iisc.ac.in/src/wspire.php): 88 speakers and five
  recording devices; download portal requires further inspection.
- [wTIMIT access instructions](https://github.com/mborsdorf/wTIMIT2mix):
  contact the corpus author. No access request has been sent on the user's behalf.

## Controlled decoding experiment: turbo beam size 5

The bundled server help reports a default beam size of -1. A separate server
was launched with `--beam-size 5`, keeping the model, CPU backend, language,
temperature and inputs unchanged. Evidence: `public-whispers-turbo-beam5.json`.

All 15 requests succeeded. Literal WER fell from 13/112 (11.61%) to 11/112
(9.82%), but the changed difficult sentences remained incorrect. One malformed
phrase became shorter, improving edit distance without recovering the intended
meaning; another incorrect verb phrase changed to a different incorrect phrase.
This is not sufficient evidence to promote the setting. No app change made.
Next accuracy experiments must consider whole-sentence correctness as well as
word edits, and verify against independent recordings before promotion.

## Full large-v3 comparison

Downloaded `ggml-large-v3-q5_0.bin` from the whisper.cpp publisher:
https://huggingface.co/ggerganov/whisper.cpp/tree/main
The approximately 1.08 GB model remains evaluation-only, outside the app bundle.
Same CPU server defaults and identical public inputs as the Turbo baseline.

Evidence: `public-whispers-large-v3.json`, complete with 15 successful requests.
13/112 word edits (11.61% WER), identical aggregate error count to Turbo.
Median recognition request: 3168 ms. Some words improved, others regressed.
The full model is not promoted: no aggregate accuracy gain and higher latency.
The temporary model server was shut down after evaluation.

Next check: compare the app's actual quiet-audio normalization path with the
raw-audio benchmarks. Current results bypass capture and normalization; do not
assume the front end helps or hurts until that difference is measured.

## Bounded-gain comparison

Ran all 15 inputs through a JavaScript mirror of the gain calculation in
`AudioCapture.swift`: RMS target 1300, peak cap 29490, max gain 12, skip RMS <=3.
Rounding uses ties away from zero, matching Swift. This is an offline formula
comparison, not a live microphone or direct Swift integration test.
Run with `AAVAI_EVAL_NORMALIZE=1` and a new `AAVAI_EVAL_OUTPUT` path.

Evidence: `public-whispers-turbo-normalized.json`. All requests succeeded;
13/112 word edits (11.61%) remained. Amplifying these already-decodable whispers
did not improve overall accuracy. This does not justify removing the app's
gain control or increasing amplification further. It does rule out simple
gain adjustment as the remedy for this set's remaining recognition errors.
No installed app changes were made. Temporary test server was stopped.

## Adaptive confidence fallback — 2026-09-13

Whisper `verbose_json` exposed average decoder log-probability and word
probabilities. On the same 15 CLARIS clips, selecting the higher-confidence
candidate from the two already bundled models reduced literal errors from
Turbo's 13/112 (11.61%) to 10/112 (8.93%). The production rule is narrower:
Turbo remains primary and small.en is queried only when Turbo average log-prob
is at or below -0.2; the fallback replaces it only with a higher score.

This rule was independently checked on 24 evenly spaced CSTR HERALD clean/noisy
clips (136 words). Turbo had 3 errors (2.21%), small.en had 9 (6.62%), and the
integrated adaptive backend had 2 (1.47%), with 24/24 successful requests.
Evidence: `public-whispers-{turbo,small}-confidence.json` and
`cstr/{confidence-turbo,confidence-small,adaptive-integrated}.json`.

Installed-build verification recovered the exact difficult phrase “Jane may
earn more money by working hard” where Turbo alone produced “walking out.” On
another noisy sample it improved a two-edit result to a one-edit result but did
not recover the correct word. This is a measured improvement, not perfect
recognition or evidence of parity with Wispr Flow.

## Final-output meaning guard — 2026-09-13

The local cleanup model initially increased the adaptive CLARIS score from
10/112 raw edits to 11/112 by replacing “while” with “when.” A production guard
now rejects cleanup output containing words that are not an ordered subset of
the filler-stripped transcript. This still permits punctuation, capitalization,
structure, and deletion of fillers/false starts, but prevents speculative word
substitution. The same 15-output evaluation returned to 10/112 with no request
failures. Evidence: `public-whispers-adaptive-cleaned.json` (failing baseline)
and `public-whispers-adaptive-cleaned-guarded.json` (guarded result).

## Rejected follow-up experiments — 2026-09-13

- Applying the same confidence fallback to Turbo beam size 5 still produced
  10/112 errors, so it did not improve the current adaptive result.
- Pre-emphasis at alpha 0.97 worsened Turbo from 13/112 to 15/112 errors and
  destabilized otherwise recognizable phrases. Evidence:
  `public-whispers-turbo-preemphasis97.json`.
- Temperature sampling and local-Qwen arbitration did not recover the remaining
  difficult phrases reliably. Neither is promoted.
- The Hugging Face `jankoko/PALF-LF-Whisper-small` candidate was rejected before
  download. Its own wTIMIT-US model card reports 11.9% whispered WER versus
  11.7% for its unaugmented fine-tuned baseline and says the difference is not
  statistically significant. It has no hosted inference provider, so conversion
  would add temporary PyTorch/Transformers dependencies and a model download
  without positive evidence. No package or model was installed for this check.

## Whispered-corpus fine-tune evaluation — 2026-09-13

The Apache-2.0 `burakaydinofficial/whisper-small-24lang` model is an unmodified
Whisper-small fine-tuned on a CC0 multilingual whispered corpus. It was downloaded
to an isolated temporary directory, converted with whisper.cpp's standard
converter, quantized to Q5_0, and tested on the identical evaluation inputs.

It regressed the CLARIS set to 16/112 errors (14.29%), versus 10/112 (8.93%) for
the production adaptive pair. Although it recovered one `cattle` substitution,
it also collapsed the six-word `she is thinner than I am` sample to the single
invented word `Justinidenium` with misleadingly high decoder confidence.
Evidence: `public-whispers-small-24lang-confidence.json`.

The independent 24-clip CSTR gate also regressed to 9/136 errors (6.62%), versus
2/136 (1.47%) for the production adaptive backend, and offered no improvement
on its remaining failures. Evidence: `cstr/confidence-small-24lang.json`. The
candidate is rejected for both accuracy and unsafe confidence calibration. Its
temporary model weights, converted files, and Python environment were deleted
after the benchmark; it was not added to the app.

The remaining `SpeechResearch/wtimit-base-normal-all-nofreeze` checkpoint was
screened without downloading weights. It is Wav2Vec2-CTC rather than Whisper,
has only an unverified 9.99% metric from an incompletely documented evaluation
split, and its generated model card leaves intended uses and limitations blank.
It is incompatible with the app's current whisper.cpp runtime and does not
provide enough trustworthy evidence to justify adding a second ASR engine.

## Parakeet cross-architecture evaluation — 2026-09-13

NVIDIA Parakeet TDT 0.6B v3 was tested through whisper.cpp's already-built
Parakeet CLI using the MIT-published GGML Q4_0 conversion (the underlying model
is CC-BY-4.0). The model file was evaluation-only and was never added to AavAI.
The benchmark scripts now accept `AAVAI_EVAL_PARAKEET_MODEL` so this test is
reproducible without changing production code.

Parakeet was the first candidate to beat the production pair on the curated
CLARIS examples: 7/112 errors (6.25%) versus adaptive Whisper's 10/112 (8.93%).
It recovered `working hard`, `cattle`, and `neighbours`, and completed each clip
in roughly 0.27–0.43 seconds including process/model startup. Evidence:
`public-whispers-parakeet-q4.json`.

It failed the independent promotion gate: 5/136 errors (3.68%) on the 24 CSTR
HERALD clean/noisy clips versus adaptive Whisper's 2/136 (1.47%). It introduced
errors on clean speech and exposes no decoder confidence through the current CLI
for a safe fallback rule. Therefore it is not promoted or bundled. The temporary
339 MB model was deleted after testing. Evidence: `cstr/parakeet-q4.json`.
