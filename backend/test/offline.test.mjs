import test from 'node:test';
import assert from 'node:assert/strict';
import { LocalProvider, createProvider } from '../src/providers.mjs';

test('offline provider refuses remote inference endpoints', () => {
  for (const option of ['whisperURL', 'whisperFallbackURL', 'ollamaURL']) {
    assert.throws(() => new LocalProvider({ [option]: 'https://example.com' }), /loopback/);
  }
});

test('offline build cannot select a cloud provider', t => {
  const previous = process.env.AAVAI_PROVIDER;
  t.after(() => { if (previous === undefined) delete process.env.AAVAI_PROVIDER; else process.env.AAVAI_PROVIDER = previous; });
  process.env.AAVAI_PROVIDER = 'openai';
  assert.throws(() => createProvider(), /disabled/);
});

test('local inference requests reject HTTP redirects', async t => {
  const original = globalThis.fetch;
  t.after(() => { globalThis.fetch = original; });
  let redirect;
  globalThis.fetch = async (_url, options) => { redirect = options.redirect; return Response.json({ text: 'test' }); };
  await new LocalProvider().transcribe(new Uint8Array([1]), { dictionary: [] });
  assert.equal(redirect, 'error');
});
