# English comparison protocol v1

No real corpus or Flow comparison is fabricated by these tools. Existing small
CLARIS/CSTR reports are regression evidence only. Synthetic backend test fixtures
exercise validators and must never be used as product evidence.

## Corpus manifest

JSON object: `version: "aavai-english-v1"`, `utterances: [...]`.
Each utterance requires:

- `id`, `speaker`, `split` (`development` or `final`).
- `reference` (verbatim), `audioSHA256` (actual file SHA-256), `source`.
- `rights: { basis: "licensed" | "consented", evidence: "license/consent record" }`.
- `conditions`: labels from normal, whisper, accent, noise, correction, name,
  number, list, email, technical. Whispers must be genuinely whispered recordings.

At least 300 utterances, 12 speakers, disjoint speakers between splits, multiple
speakers and whispers in both splits are enforced. The validator cannot establish
that consent is genuine or a file really contains whispers: a curator must verify
the license, audio hashes, recordings and labels before freezing.

Keep audio out of Git. Keep final audio/references away from prompt/model tuning.
Before final testing, freeze the corpus JSON and model/formatter configuration.
`node scripts/evaluation/report.mjs manifest.json` validates and emits the digest.
The digest is SHA-256 over JSON.stringify(parsed manifest); preserve array and key
order. This is reproducibility metadata, not access control or proof of blindness.

## Paired run

Required metadata: `corpusSHA256`, `frozenConfiguration`, `flowVersion`,
`flowSettings`, `captureRoute`. `records` must exactly cover final utterances.
Each record: `id`, `audioSHA256`, `blindedReview: true`, `reviewer`, and `aavai` /
`flow` objects containing `raw`, `final`, `correctionEdits`, `criticalMeaningErrors`.

Correction edits are human-reviewed token insertions/deletions/substitutions to
produce an acceptable final transcript; the reviewer must not know the engine.
Do not use raw WER as a substitute for this review. Review negation, names,
quantities, dates, URLs and instructions even when aggregate WER improves.

`node scripts/evaluation/report.mjs manifest.json paired-run.json` computes raw
WER, paired correction-edit difference, speaker and whisper breakdowns. Raw WER
normalization is implemented and documented in `scripts/evaluation/protocol.mjs`.
Do not describe 1−WER as accuracy. Negative correction-edit difference favors AavAI.

The report deliberately returns `review-required`, never `passed`: speaker-level
paired uncertainty, condition-level review, physical microphone trials, latency,
memory, thermal, insertion and offline network tests remain separate mandatory
gates. Missing data is invalid, not a zero-error result. Any observed AavAI critical
meaning error blocks promotion. Use Flow's free allowance without bypassing limits.
