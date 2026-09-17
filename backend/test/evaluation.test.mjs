import test from 'node:test';
import assert from 'node:assert/strict';
import { validateCorpus, words, editDistance, compareFinal, corpusDigest } from '../../scripts/evaluation/protocol.mjs';

function corpus() {
  return { version: 'aavai-english-v1', utterances: Array.from({ length: 300 }, (_, i) => ({
    id: String(i), speaker: `speaker-${i % 12}`, split: i % 12 < 8 ? 'development' : 'final',
    reference: 'do not send 15 dollars', audioSHA256: 'a'.repeat(64), source: 'test fixture only',
    rights: { basis: 'consented', evidence: 'synthetic test fixture, not a real corpus' },
    conditions: ['normal', 'whisper', 'accent', 'noise', 'correction', 'name', 'number', 'list', 'email', 'technical'],
  })) };
}

test('corpus gate refuses small datasets, rights gaps and speaker leakage', () => {
  assert.ok(validateCorpus({}).length);
  const c = corpus(); assert.deepEqual(validateCorpus(c), []);
  c.utterances[0].split = 'final';
  c.utterances[1].rights = {};
  assert.ok(validateCorpus(c).some(x => x.includes('leakage')));
  assert.ok(validateCorpus(c).some(x => x.includes('rights')));
});

test('WER normalization preserves negation and numbers', () => {
  assert.equal(editDistance(words('Do not send 15 dollars.'), words('do send 50 dollars')), 2);
  assert.deepEqual(words(' Hello, WORLD! '), ['hello', 'world']);
});

test('unpaired output cannot pass and even equal paired text requires review', () => {
  const c = corpus();
  assert.equal(compareFinal(c, {}).status, 'invalid');
  const result = { raw: 'do not send 15 dollars', final: 'Do not send 15 dollars.', correctionEdits: 0, criticalMeaningErrors: 0 };
  const run = { corpusSHA256: corpusDigest(c), frozenConfiguration: 'test', flowVersion: 'test', flowSettings: 'test', captureRoute: 'test',
    records: c.utterances.filter(x => x.split === 'final').map(x => ({ id: x.id, audioSHA256: x.audioSHA256,
      blindedReview: true, reviewer: 'fixture', aavai: { ...result }, flow: { ...result } })) };
  assert.equal(compareFinal(c, run).status, 'review-required');
  run.records[0].aavai.criticalMeaningErrors = 1;
  assert.equal(compareFinal(c, run).status, 'blocked-critical-meaning-errors');
  run.records.push(run.records[0]);
  assert.equal(compareFinal(c, run).status, 'invalid');
});
