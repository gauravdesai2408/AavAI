import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/server.mjs";

test("health and development pipeline", async t => {
  const app = createApp();
  await new Promise(resolve => app.listen(0, "127.0.0.1", resolve));
  t.after(() => app.close());
  const { port } = app.address();
  const base = `http://127.0.0.1:${port}`;
  const health = await (await fetch(`${base}/health`)).json();
  assert.equal(health.status, "ok");
  assert.equal(health.dependencies.provider, "development");
  const transcription = await (await fetch(`${base}/v1/transcribe`, { method: "POST", body: new Uint8Array([1, 2]) })).json();
  assert.match(transcription.text, /development/);
  const cleanup = await (await fetch(`${base}/v1/cleanup`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ transcript: "um hello", locale: "en", dictionary: [], context: { category: "generic", nearbyText: "", isSecure: false } })
  })).json();
  assert.equal(cleanup.text, "Hello.");
});
