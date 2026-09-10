# Whispered English baseline — 2026-09-09

Model: installed Whisper small.en, CPU, local backend.
Corpus: CSTR NAM TIMIT Plus (see SOURCE.md for attribution and license).
Subset: TIMIT-NOISY headset recordings 001–012, one speaker, background noise.
Audio converted to mono 16 kHz PCM16 using macOS afconvert.

Command:
`AAVAI_EVAL_CONDITIONS=TIMIT-NOISY node scripts/evaluate-whisper-corpus.mjs .evaluation/cstr/CSTR-NAM-TIMIT-Plus 12`

Result: 12 word edits / 74 reference words = **16.22% literal word-error rate**.
All 12 requests returned HTTP 200. Recognition time approximately 575–638 ms.
The scorer treats “thirty” and “30” as different tokens; this is a literal WER,
not a semantic error metric. No reference words were supplied as ASR prompts.

Examples requiring improvement:

| Reference | Recognized |
| --- | --- |
| Is this seesaw safe? | Is this Cecil safe? |
| Those thieves stole thirty jewels. | These leaves restore 30 jewels. |
| Jane may earn more money by working hard. | She may earn more money by working hard. |
| He will allow a rare lie. | He will allow the red light. |

Six utterances were exact matches under the scorer. This is preliminary evidence
on actual whispers, not a general accuracy claim or comparison against Wispr Flow.
Compare candidate models on this development subset, then test a disjoint subset.
