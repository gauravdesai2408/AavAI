import { readFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";

const baseURL = process.env.AAVAI_EVAL_URL || "http://127.0.0.1:8787";
const audioPath = new URL("../.tools/whisper.cpp/samples/jfk.wav", import.meta.url);
const audio = await readFile(audioPath);

const started = performance.now();
const transcriptionResponse = await fetch(`${baseURL}/v1/transcribe`, {
  method: "POST",
  headers: { "content-type": "audio/wav", "x-locale": "en" },
  body: audio
});
const transcription = await transcriptionResponse.json();
if (!transcriptionResponse.ok) throw new Error(transcription.error || "transcription failed");
const transcribed = performance.now();

const cleanupResponse = await fetch(`${baseURL}/v1/cleanup`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    transcript: transcription.text,
    context: { bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit", category: "document", nearbyText: "", isSecure: false },
    locale: "en",
    dictionary: []
  })
});
const cleanup = await cleanupResponse.json();
if (!cleanupResponse.ok) throw new Error(cleanup.error || "cleanup failed");
const finished = performance.now();

if (!/fellow Americans/i.test(transcription.text) || !/your country/i.test(cleanup.text)) {
  throw new Error(`accuracy check failed: ${JSON.stringify({ transcription, cleanup })}`);
}

console.log(JSON.stringify({
  transcription: transcription.text,
  cleaned: cleanup.text,
  transcriptionMilliseconds: Math.round(transcribed - started),
  cleanupMilliseconds: Math.round(finished - transcribed),
  releaseToResultMilliseconds: Math.round(finished - started)
}, null, 2));
