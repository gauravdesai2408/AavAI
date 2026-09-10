import { readFile, readdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";

const root = resolve(process.argv[2] || ".evaluation/cstr/CSTR-NAM-TIMIT-Plus");
const limit = Number(process.argv[3] || 12);
const conditions = process.env.AAVAI_EVAL_CONDITIONS?.split(",") || ["HERALD-CLEAN", "HERALD-NOISY", "TIMIT-NOISY"];
const verbose = process.env.AAVAI_EVAL_VERBOSE === "1";
const parakeetModel = process.env.AAVAI_EVAL_PARAKEET_MODEL;
const parakeetCLI = process.env.AAVAI_EVAL_PARAKEET_CLI || ".tools/whisper.cpp/build/bin/parakeet-cli";
if (conditions.some(value => !["HERALD-CLEAN", "HERALD-NOISY", "TIMIT-NOISY"].includes(value))) throw new Error("Unknown condition");
if (!Number.isInteger(limit) || limit < 1 || limit > 500) throw new Error("Sample limit must be 1–500");
const tokens = text => text.toLowerCase().replace(/[^a-z0-9'\s]/g, " ").split(/\s+/).filter(Boolean);
function errors(reference, actual) {
  let row = actual.map((_, i) => i + 1); row.unshift(0);
  for (let i = 1; i <= reference.length; i++) {
    const next = [i];
    for (let j = 1; j <= actual.length; j++) next[j] = Math.min(next[j - 1] + 1, row[j] + 1, row[j - 1] + Number(reference[i - 1] !== actual[j - 1]));
    row = next;
  }
  return row[actual.length];
}
const temporary = await mkdtemp(join(tmpdir(), "aavai-corpus-"));
let totalErrors = 0, totalWords = 0, count = 0, failures = 0;
const results = [];
try {
  for (const condition of conditions) {
    const files = (await readdir(join(root, condition))).filter(name => name.endsWith("_headset.wav")).sort();
    // Evenly spaced deterministic samples; never feed reference text to ASR.
    const selected = files.filter((_, index) => index % Math.max(1, Math.floor(files.length / limit)) === 0).slice(0, limit);
    for (const name of selected) {
      const stem = name.replace("_headset.wav", "");
      const reference = (await readFile(join(root, condition.startsWith("HERALD") ? "HERALD-TEXT" : "TIMIT-TEXT", `${stem}.txt`), "utf8")).trim();
      const wav = join(temporary, "sample.wav");
      execFileSync("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", join(root, condition, name), wav]);
      const started = performance.now();
      const audio = await readFile(wav);
      let payload, status;
      if (parakeetModel) {
        payload = { text: execFileSync(parakeetCLI, ["--model", parakeetModel, "--file", wav, "--no-gpu"], {
          encoding: "utf8", stdio: ["ignore", "pipe", "ignore"]
        }).trim() };
        status = 200;
      } else {
        const form = new FormData();
        form.set("file", new Blob([audio], { type: "audio/wav" }), "dictation.wav");
        form.set("response_format", verbose ? "verbose_json" : "json");
        form.set("temperature", "0.0");
        form.set("language", "en");
        const direct = process.env.AAVAI_EVAL_WHISPER_URL;
        const response = await fetch(direct ? `${direct}/inference` : `${process.env.AAVAI_EVAL_URL || "http://127.0.0.1:8787"}/v1/transcribe`, {
          method: "POST", headers: direct ? {} : { "content-type": "audio/wav", "x-locale": "en" },
          body: direct ? form : audio, signal: AbortSignal.timeout(45000)
        });
        payload = await response.json(); status = response.status;
      }
      const expected = tokens(reference), actual = tokens(payload.text || "");
      const wordErrors = errors(expected, actual);
      totalWords += expected.length; totalErrors += wordErrors; count++;
      if (status !== 200) failures++;
      const logprobs = (payload.segments || []).map(segment => Number(segment.avg_logprob)).filter(Number.isFinite);
      const result = { condition, name, reference, text: payload.text || "", status,
        avgLogprob: logprobs.length ? logprobs.reduce((sum, value) => sum + value, 0) / logprobs.length : null,
        wordErrors, words: expected.length, milliseconds: Math.round(performance.now() - started) };
      results.push(result);
      console.log(JSON.stringify(result));
      if (process.env.AAVAI_EVAL_OUTPUT) await writeFile(process.env.AAVAI_EVAL_OUTPUT, JSON.stringify({ complete: false, results }, null, 2));
    }
  }
  const summary = { samples: count, requestFailures: failures, totalErrors, totalWords, wordErrorRate: totalWords ? totalErrors / totalWords : null };
  console.log(JSON.stringify(summary));
  if (process.env.AAVAI_EVAL_OUTPUT) await writeFile(process.env.AAVAI_EVAL_OUTPUT, JSON.stringify({ complete: true, summary, results }, null, 2));
} finally {
  await rm(temporary, { recursive: true, force: true });
}
