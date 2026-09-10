import test from "node:test";
import assert from "node:assert/strict";
import { LocalProvider, isNonSpeechTranscript, sanitizeModelText, stripFillers } from "../src/providers.mjs";

test("silent PCM is rejected before model inference, but quiet samples are sent", async t => {
  const wav = Buffer.alloc(48);
  wav.write("RIFF", 0); wav.writeUInt32LE(40, 4); wav.write("WAVEfmt ", 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(16000, 24); wav.writeUInt32LE(32000, 28);
  wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write("data", 36); wav.writeUInt32LE(4, 40);
  let calls = 0;
  const original = globalThis.fetch;
  t.after(() => { globalThis.fetch = original; });
  globalThis.fetch = async () => { calls++; return Response.json({ text: "Quiet words" }); };
  const provider = new LocalProvider();
  await assert.rejects(provider.transcribe(wav, { dictionary: [] }), /no speech detected/);
  assert.equal(calls, 0);
  wav.writeInt16LE(1, 44);
  assert.equal(await provider.transcribe(wav, { dictionary: [] }), "Quiet words");
  assert.equal(calls, 1);
});

test("cleanup sanitizer removes leaked context labels", () => {
  assert.equal(
    sanitizeModelText('"Hello Gaurav.\nNearby text: Previous sentence.\nDictionary: [AavAI]"'),
    "Hello Gaurav."
  );
});

test("cleanup sanitizer removes leaked XML boundaries", () => {
  assert.equal(sanitizeModelText("<dictation>\nHello.\n</dictation>"), "Hello.");
  assert.equal(sanitizeModelText("<dictation>\n</dictation>"), "");
});

test("Whisper non-speech markers are recognized", () => {
  assert.equal(isNonSpeechTranscript("[BLANK_AUDIO]"), true);
  assert.equal(isNonSpeechTranscript("(silence)"), true);
  assert.equal(isNonSpeechTranscript("(mumbles)"), true);
  assert.equal(isNonSpeechTranscript("[Singing] [Silence]"), true);
  assert.equal(isNonSpeechTranscript("She mumbles when tired."), false);
  assert.equal(isNonSpeechTranscript("Hello there"), false);
});

test("fillers are removed deterministically", () => {
  assert.equal(stripFillers("um hey Sarah, uh can we talk, you know tomorrow"), "hey Sarah, can we talk, tomorrow");
});

test("local provider sends audio to Whisper and transcript to Ollama", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    if (String(url).endsWith("/inference")) return Response.json({ text: "um hello there" });
    if (String(url).endsWith("/api/chat")) return Response.json({ message: { content: "Hello there." } });
    return Response.json({ status: "ok" });
  };
  const provider = new LocalProvider();
  const transcript = await provider.transcribe(new Uint8Array([1]), { locale: "en", dictionary: ["AavAI"] });
  const cleaned = await provider.cleanup({ transcript, dictionary: ["AavAI"], context: { category: "workChat", nearbyText: "" } });
  assert.equal(transcript, "um hello there");
  assert.equal(cleaned.text, "Hello there.");
  assert.match(calls[0].url, /\/inference$/);
  assert.match(calls[1].url, /\/api\/chat$/);
});

test("cleanup cannot substitute words that were not dictated", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async () => Response.json({ message: { content: "Where were you when you were away?" } });
  const provider = new LocalProvider();
  const cleaned = await provider.cleanup({
    transcript: "Where were you while you were away?",
    dictionary: [],
    context: { category: "generic", nearbyText: "" }
  });
  assert.equal(cleaned.text, "Where were you while you were away?");
  assert.deepEqual(cleaned.warnings, ["meaningGuard"]);
});

test("accuracy fallback replaces a low-confidence transcript with a stronger candidate", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const calls = [];
  globalThis.fetch = async url => {
    calls.push(String(url));
    if (String(url).startsWith("http://primary")) return Response.json({
      text: "Jane may earn more money by walking out.", segments: [{ avg_logprob: -0.27 }]
    });
    return Response.json({
      text: "Jane may earn more money by working hard.", segments: [{ avg_logprob: -0.08 }]
    });
  };
  const provider = new LocalProvider({ whisperURL: "http://primary", whisperFallbackURL: "http://fallback" });
  assert.equal(
    await provider.transcribe(new Uint8Array([1]), { dictionary: [] }),
    "Jane may earn more money by working hard."
  );
  assert.equal(calls.length, 2);
});

test("accuracy fallback is skipped for a confident primary transcript", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    return Response.json({ text: "This was easy for us.", segments: [{ avg_logprob: -0.08 }] });
  };
  const provider = new LocalProvider({ whisperURL: "http://primary", whisperFallbackURL: "http://fallback" });
  assert.equal(await provider.transcribe(new Uint8Array([1]), { dictionary: [] }), "This was easy for us.");
  assert.equal(calls, 1);
});

test("accuracy fallback failure preserves the usable primary transcript", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async url => {
    if (String(url).startsWith("http://primary")) {
      return Response.json({ text: "Quiet words", segments: [{ avg_logprob: -0.5 }] });
    }
    throw new Error("fallback unavailable");
  };
  const provider = new LocalProvider({ whisperURL: "http://primary", whisperFallbackURL: "http://fallback" });
  assert.equal(await provider.transcribe(new Uint8Array([1]), { dictionary: [] }), "Quiet words");
});

test("local provider bounds a stalled Whisper request", async t => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (_url, options = {}) => new Promise((resolve, reject) => {
    options.signal?.addEventListener("abort", () => reject(options.signal.reason), { once: true });
  });

  const provider = new LocalProvider({ requestTimeoutMilliseconds: 20 });
  const outcome = await Promise.race([
    provider.transcribe(new Uint8Array([1]), { locale: "en", dictionary: [] })
      .then(() => "resolved", () => "rejected"),
    new Promise(resolve => setTimeout(() => resolve("hung"), 100))
  ]);

  assert.equal(outcome, "rejected");
});
