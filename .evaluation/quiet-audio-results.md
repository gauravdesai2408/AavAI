# Quiet audio baseline — 2026-09-09

Command: `node scripts/evaluate-quiet-audio.mjs`

Target: installed local backend on port 8787, Whisper small.en.
Input: bundled 11-second JFK WAV, compared against its reference words.

| Input | Word error rate | Recognition time |
| --- | --- | --- |
| Original | 0% | 750 ms |
| Attenuated 30 dB | 0% | 679 ms |
| Attenuated 30 dB, normalized | 0% | 679 ms |
| Attenuated 45 dB | 0% | 692 ms |
| Attenuated 45 dB, normalized | 0% | 694 ms |
| Digital silence | Rejected, HTTP 422 | 589 ms |

This measures backend behavior on one voiced recording. It does not test the
microphone, actual whispered speech, accent diversity, or Wispr Flow parity.
Normalization did not improve word accuracy in this test. The client’s lowered
capture threshold and normalization need additional noise and whisper testing.

Next: evaluate actual headset whispers from CSTR NAM TIMIT Plus; compare
recognition settings/models on held-out utterances rather than tune to JFK.
