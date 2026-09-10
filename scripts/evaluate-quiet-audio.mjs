import { readFile } from "node:fs/promises";
import { LocalProvider } from "../backend/src/providers.mjs";

// Attenuated voiced speech is a volume regression test, not a whisper corpus.
const input = await readFile(new URL("../.tools/whisper.cpp/samples/jfk.wav", import.meta.url));
let dataOffset = 0;
let dataSize = 0;
for (let offset = 12; offset + 8 <= input.length;) {
  const size = input.readUInt32LE(offset + 4);
  if (input.toString("ascii", offset, offset + 4) === "data") {
    dataOffset = offset + 8; dataSize = size; break;
  }
  offset += 8 + size + (size % 2);
}
if (!dataOffset) throw new Error("Sample WAV has no data chunk");
const reference = "and so my fellow americans ask not what your country can do for you ask what you can do for your country";
const words = text => text.toLowerCase().replace(/[^a-z0-9\s]/g, "").trim().split(/\s+/).filter(Boolean);
function wordErrorRate(text) {
  const expected = words(reference), actual = words(text);
  let row = Array.from({ length: actual.length + 1 }, (_, i) => i);
  for (let i = 1; i <= expected.length; i++) {
    const next = [i];
    for (let j = 1; j <= actual.length; j++) {
      next[j] = Math.min(next[j - 1] + 1, row[j] + 1, row[j - 1] + (expected[i - 1] === actual[j - 1] ? 0 : 1));
    }
    row = next;
  }
  return row[actual.length] / expected.length;
}
function audioVariant(scale, normalize) {
  const audio = Buffer.from(input);
  let energy = 0, peak = 0;
  for (let offset = dataOffset; offset < dataOffset + dataSize; offset += 2) {
    const value = Math.round(input.readInt16LE(offset) * scale);
    audio.writeInt16LE(value, offset);
    energy += value * value; peak = Math.max(peak, Math.abs(value));
  }
  const rms = Math.sqrt(energy / (dataSize / 2));
  const gain = normalize && rms > 3 && peak > 0 ? Math.max(1, Math.min(12, 1300 / rms, 29490 / peak)) : 1;
  for (let offset = dataOffset; offset < dataOffset + dataSize; offset += 2) {
    audio.writeInt16LE(Math.round(audio.readInt16LE(offset) * gain), offset);
  }
  return { audio, rms, gain };
}
const results = [];
for (const [name, scale, normalize] of [
  ["normal", 1, false], ["quiet -30dB", 10 ** (-30 / 20), false],
  ["quiet -30dB normalized", 10 ** (-30 / 20), true],
  ["quiet -45dB", 10 ** (-45 / 20), false],
  ["quiet -45dB normalized", 10 ** (-45 / 20), true], ["digital silence", 0, true]
]) {
  const { audio, rms, gain } = audioVariant(scale, normalize);
  const started = performance.now();
  const direct = process.env.AAVAI_EVAL_WHISPER_URL;
  const response = direct ? await (async () => {
    try {
      const text = await new LocalProvider({ whisperURL: direct }).transcribe(audio, { locale: "en", dictionary: [] });
      return Response.json({ text });
    } catch (error) { return Response.json({ error: error.message }, { status: error.status || 500 }); }
  })() : await fetch(`${process.env.AAVAI_EVAL_URL || "http://127.0.0.1:8787"}/v1/transcribe`, {
    method: "POST", headers: { "content-type": "audio/wav", "x-locale": "en" }, body: audio,
    signal: AbortSignal.timeout(45000)
  });
  const payload = await response.json();
  const result = { name, status: response.status, rms, gain, milliseconds: Math.round(performance.now() - started),
    text: payload.text ?? "", wordErrorRate: scale ? wordErrorRate(payload.text ?? "") : null,
    passed: scale ? response.ok && wordErrorRate(payload.text ?? "") <= 0.1 : response.status === 422 };
  results.push(result);
  console.log(JSON.stringify(result));
}
console.log(JSON.stringify({ scope: "One voiced sample at controlled volumes; does not establish whispered-speech accuracy", passed: results.filter(r => r.passed).length, total: results.length }));
if (results.some(result => !result.passed)) process.exitCode = 1;
