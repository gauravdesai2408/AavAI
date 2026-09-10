// Evaluate original English whisper inputs published by the CLARIS authors.
// Demo examples are curated, not a representative held-out benchmark.
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const base = 'https://claris-w2s.github.io/CLARIS/';
const output = process.env.AAVAI_EVAL_OUTPUT;
if (!output) throw new Error('Set AAVAI_EVAL_OUTPUT to a new results JSON path');
const endpoint = process.env.AAVAI_EVAL_WHISPER_URL || 'http://127.0.0.1:8082';
const parakeetModel = process.env.AAVAI_EVAL_PARAKEET_MODEL;
const parakeetCLI = process.env.AAVAI_EVAL_PARAKEET_CLI || '.tools/whisper.cpp/build/bin/parakeet-cli';
const normalize = process.env.AAVAI_EVAL_NORMALIZE === '1';
const verbose = process.env.AAVAI_EVAL_VERBOSE === '1';
const preemphasis = Number(process.env.AAVAI_EVAL_PREEMPHASIS || 0);
if (!Number.isFinite(preemphasis) || preemphasis < 0 || preemphasis >= 1) throw new Error('AAVAI_EVAL_PREEMPHASIS must be between 0 and 1');
// Mirrors AudioCapture.swift's bounded PCM16 gain for this offline comparison.
function prepareAudio(input) {
  const audio = Buffer.from(input);
  for (let offset = 12; offset + 8 <= audio.length;) {
    const size = audio.readUInt32LE(offset + 4), start = offset + 8;
    if (start + size > audio.length) throw new Error('Truncated WAV');
    if (audio.toString('ascii', offset, offset + 4) === 'data') {
      let energy = 0, peak = 0;
      if (size < 2 || size % 2) throw new Error('Invalid PCM16 data');
      for (let i = start; i < start + size; i += 2) {
        const value = audio.readInt16LE(i);
        energy += value * value; peak = Math.max(peak, Math.abs(value));
      }
      const rms = Math.sqrt(energy / (size / 2));
      const gain = normalize && rms > 3 && peak > 0 ? Math.max(1, Math.min(12, 1300 / rms, 29490 / peak)) : 1;
      const samples = [];
      for (let i = start; i < start + size; i += 2) samples.push(audio.readInt16LE(i) * gain);
      const filtered = samples.map((value, index) => preemphasis ? value - preemphasis * (samples[index - 1] || 0) : value);
      const filteredPeak = filtered.reduce((maximum, value) => Math.max(maximum, Math.abs(value)), 0);
      const outputScale = filteredPeak > 29490 ? 29490 / filteredPeak : 1;
      for (let index = 0; index < filtered.length; index++) {
        const value = filtered[index] * outputScale;
        audio.writeInt16LE(Math.sign(value) * Math.round(Math.abs(value)), start + index * 2);
      }
      return {audio, rms, gain, preemphasis};
    }
    offset = start + size + (size % 2);
  }
  throw new Error('Missing WAV data');
}
async function get(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(45000) });
  if (!response.ok) throw new Error(`${response.status}: ${url}`);
  return response;
}
const source = await (await get(`${base}scripts.js`)).text();
// Parse only literal metadata, never execute remote JavaScript.
const english = source.split('containerId: "HindiContainer"')[0];
const samples = [];
for (const section of english.split('exptId: ').slice(1)) {
  const group = section.match(/^"([A-Za-z0-9_]+)"/)?.[1];
  if (!['wTIMIT_44', 'wTIMIT_Unseen_4', 'IndianAccentEnglish'].includes(group)) continue;
  for (const match of section.matchAll(/inputAudio:\s*"([\w.]+)"\s*,\s*speaker:\s*"([\w]+)"\s*,\s*text:\s*"([^"\n]+)"/g)) {
    samples.push({ group, file: match[1], speaker: match[2], reference: match[3] });
  }
}
if (samples.length !== 15) throw new Error(`Source changed: expected 15 English inputs, found ${samples.length}`);
const tokens = text => text.toLowerCase().replace(/[^a-z0-9'\s]/g, ' ').split(/\s+/).filter(Boolean);
function distance(a, b) {
  let row = Array.from({length: b.length + 1}, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const next = [i];
    for (let j = 1; j <= b.length; j++) next[j] = Math.min(next[j-1]+1, row[j]+1, row[j-1]+Number(a[i-1] !== b[j-1]));
    row = next;
  }
  return row[b.length];
}
const temporary = await mkdtemp(join(tmpdir(), 'aavai-public-whispers-'));
const results = [];
try {
  for (const sample of samples) {
    const url = `${base}resources/audio/${sample.group}/ground_truth/${sample.file}`;
    const mp3 = join(temporary, 'input.mp3'), wav = join(temporary, 'input.wav');
    await writeFile(mp3, new Uint8Array(await (await get(url)).arrayBuffer()));
    execFileSync('/usr/bin/afconvert', ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', mp3, wav]);
    const prepared = prepareAudio(await readFile(wav));
    await writeFile(wav, prepared.audio);
    const start = performance.now();
    let payload, status;
    if (parakeetModel) {
      payload = { text: execFileSync(parakeetCLI, ['--model', parakeetModel, '--file', wav, '--no-gpu'], {
        encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore']
      }).trim() };
      status = 200;
    } else {
      const form = new FormData();
      form.set('file', new Blob([prepared.audio], {type:'audio/wav'}), 'dictation.wav');
      form.set('response_format', verbose ? 'verbose_json' : 'json'); form.set('temperature', '0.0'); form.set('language', 'en');
      const response = await fetch(`${endpoint}/inference`, {method:'POST', body:form, signal:AbortSignal.timeout(45000)});
      payload = await response.json(); status = response.status;
    }
    const expected = tokens(sample.reference), actual = tokens(payload.text || '');
    const probabilities = (payload.segments || []).flatMap(segment => (segment.words || []).map(word => word.probability)).filter(Number.isFinite);
    const result = {...sample, url, normalized:normalize, rms:prepared.rms, gain:prepared.gain, preemphasis:prepared.preemphasis, text:payload.text || '', status, words:expected.length,
      avgLogprob: payload.segments?.length ? payload.segments.reduce((sum, segment) => sum + segment.avg_logprob, 0) / payload.segments.length : null,
      minimumWordProbability: probabilities.length ? Math.min(...probabilities) : null,
      meanWordProbability: probabilities.length ? probabilities.reduce((sum, value) => sum + value, 0) / probabilities.length : null,
      wordErrors:distance(expected, actual), milliseconds:Math.round(performance.now()-start)};
    results.push(result);
    await writeFile(output, JSON.stringify({source:base, complete:false, results}, null, 2));
    console.log(JSON.stringify(result));
  }
  const summary = {samples:results.length, speakers:new Set(results.map(x=>x.speaker)).size,
    words:results.reduce((s,x)=>s+x.words,0), errors:results.reduce((s,x)=>s+x.wordErrors,0),
    failures:results.filter(x=>x.status!==200).length};
  summary.wordErrorRate = summary.errors / summary.words;
  await writeFile(output, JSON.stringify({source:base, complete:true, summary, results}, null, 2));
  console.log(JSON.stringify(summary));
} finally {
  await rm(temporary, {recursive:true, force:true});
}
