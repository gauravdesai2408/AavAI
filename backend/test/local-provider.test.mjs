import test from "node:test";
import assert from "node:assert/strict";
import { LocalProvider, isNonSpeechTranscript, sanitizeModelText, stripFillers } from "../src/providers.mjs";

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
