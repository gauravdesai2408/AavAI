// Evaluate final cleanup output from previously captured ASR candidates.
// Reference text is used only for scoring and is never sent to the model.
import { readFile, writeFile } from "node:fs/promises";

const turbo = JSON.parse(await readFile(process.argv[2] || ".evaluation/public-whispers-turbo-confidence.json", "utf8"));
const small = JSON.parse(await readFile(process.argv[3] || ".evaluation/public-whispers-small-confidence.json", "utf8"));
const output = process.env.AAVAI_EVAL_OUTPUT;
if (!output) throw new Error("Set AAVAI_EVAL_OUTPUT to a new results JSON path");
const endpoint = process.env.AAVAI_EVAL_URL || "http://127.0.0.1:8787";
const tokens = text => text.toLowerCase().replace(/[^a-z0-9'\s]/g, " ").split(/\s+/).filter(Boolean);
function distance(a, b) {
  let row = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i++) {
    const next = [i];
    for (let j = 1; j <= b.length; j++) next[j] = Math.min(next[j - 1] + 1, row[j] + 1, row[j - 1] + Number(a[i - 1] !== b[j - 1]));
    row = next;
  }
  return row[b.length];
}

const results = [];
for (let index = 0; index < turbo.results.length; index++) {
  const primary = turbo.results[index], fallback = small.results[index];
  const selected = primary.avgLogprob <= -0.2 && fallback.avgLogprob > primary.avgLogprob ? fallback : primary;
  const response = await fetch(`${endpoint}/v1/cleanup`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      transcript: selected.text.trim(),
      context: { bundleIdentifier: null, applicationName: "AavAI evaluation", category: "generic", nearbyText: "", isSecure: false },
      locale: "en",
      dictionary: []
    }),
    signal: AbortSignal.timeout(45_000)
  });
  const payload = await response.json();
  const result = {
    file: primary.file,
    reference: primary.reference,
    raw: selected.text.trim(),
    cleaned: payload.text || "",
    status: response.status,
    words: tokens(primary.reference).length,
    rawErrors: distance(tokens(primary.reference), tokens(selected.text)),
    cleanedErrors: distance(tokens(primary.reference), tokens(payload.text || ""))
  };
  results.push(result);
  console.log(JSON.stringify(result));
}
const summary = {
  samples: results.length,
  words: results.reduce((sum, result) => sum + result.words, 0),
  rawErrors: results.reduce((sum, result) => sum + result.rawErrors, 0),
  cleanedErrors: results.reduce((sum, result) => sum + result.cleanedErrors, 0),
  failures: results.filter(result => result.status !== 200).length
};
await writeFile(output, JSON.stringify({ complete: true, summary, results }, null, 2));
console.log(JSON.stringify(summary));
