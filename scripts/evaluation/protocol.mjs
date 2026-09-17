import { createHash } from 'node:crypto';

export const protocolVersion = 'aavai-english-v1';

export function validateCorpus(corpus) {
  const errors = [];
  if (corpus.version !== protocolVersion) errors.push('Unknown protocol version');
  const rows = corpus.utterances ?? [];
  if (rows.length < 300) errors.push('At least 300 utterances required');
  const speakers = new Set(rows.map(x => x.speaker));
  if (speakers.size < 12) errors.push('At least 12 speakers required');
  const ids = new Set();
  const splits = new Map();
  const required = new Set(['normal', 'whisper', 'accent', 'noise', 'correction', 'name', 'number', 'list', 'email', 'technical']);
  for (const row of rows) {
    if (!row.id || ids.has(row.id)) errors.push(`Missing/duplicate utterance: ${row.id}`);
    ids.add(row.id);
    if (!row.speaker || !['development', 'final'].includes(row.split)) errors.push(`Invalid speaker/split: ${row.id}`);
    if (splits.has(row.speaker) && splits.get(row.speaker) !== row.split) errors.push(`Speaker leakage: ${row.speaker}`);
    splits.set(row.speaker, row.split);
    if (!row.reference?.trim() || !/^[a-f0-9]{64}$/.test(row.audioSHA256 ?? '')) errors.push(`Missing reference/audio hash: ${row.id}`);
    if (!row.source || !row.rights?.evidence || !['licensed', 'consented'].includes(row.rights?.basis)) errors.push(`Missing rights evidence: ${row.id}`);
    for (const condition of row.conditions ?? []) required.delete(condition);
  }
  if (required.size) errors.push(`Missing conditions: ${[...required].join(', ')}`);
  for (const split of ['development', 'final']) {
    const selected = rows.filter(x => x.split === split);
    if (!selected.some(x => x.conditions?.includes('whisper'))) errors.push(`Missing genuine whispers in ${split}`);
    if (new Set(selected.map(x => x.speaker)).size < 2) errors.push(`Need multiple speakers in ${split}`);
  }
  return errors;
}

// Deliberately documented normalization: Unicode NFC, English lowercase,
// punctuation replaced by spaces, whitespace collapsed. Do not convert numbers
// to words or erase negation. Raw references remain available for meaning review.
export function words(text) {
  return text.normalize('NFC').toLocaleLowerCase('en-US')
    .replace(/[^\p{L}\p{N}'’]+/gu, ' ').trim().split(/\s+/u).filter(Boolean);
}

export function editDistance(a, b) {
  let previous = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 0; i < a.length; i++) {
    const current = [i + 1];
    for (let j = 0; j < b.length; j++) current.push(Math.min(current[j] + 1, previous[j + 1] + 1, previous[j] + (a[i] === b[j] ? 0 : 1)));
    previous = current;
  }
  return previous[b.length];
}

export function corpusDigest(corpus) {
  // Hash exact serialized manifest, including order; freeze that artifact.
  return createHash('sha256').update(JSON.stringify(corpus)).digest('hex');
}

export function compareFinal(corpus, run) {
  const errors = validateCorpus(corpus);
  if (run.corpusSHA256 !== corpusDigest(corpus)) errors.push('Frozen corpus hash mismatch');
  if (!run.frozenConfiguration || !run.flowVersion || !run.flowSettings || !run.captureRoute) errors.push('Missing frozen configuration or Flow provenance');
  const final = (corpus.utterances ?? []).filter(x => x.split === 'final');
  const records = new Map();
  for (const record of run.records ?? []) {
    if (records.has(record.id)) errors.push(`Duplicate paired result: ${record.id}`);
    records.set(record.id, record);
  }
  if (records.size !== final.length) errors.push('Paired results must exactly cover the final set');
  const scores = [];
  for (const row of final) {
    const record = records.get(row.id);
    if (!record || record.audioSHA256 !== row.audioSHA256) { errors.push(`Missing/mismatched audio: ${row.id}`); continue; }
    if (!record.blindedReview || !record.reviewer) errors.push(`Missing blinded review: ${row.id}`);
    for (const engine of ['aavai', 'flow']) {
      const value = record[engine];
      if (typeof value?.raw !== 'string' || typeof value?.final !== 'string'
          || !Number.isInteger(value?.correctionEdits) || value.correctionEdits < 0
          || !Number.isInteger(value?.criticalMeaningErrors) || value.criticalMeaningErrors < 0) errors.push(`Incomplete review for ${engine}: ${row.id}`);
    }
    if (!record.aavai || !record.flow) continue;
    scores.push({ speaker: row.speaker, whisper: row.conditions.includes('whisper'),
      difference: record.aavai.correctionEdits - record.flow.correctionEdits,
      critical: record.aavai.criticalMeaningErrors,
      aavaiErrors: editDistance(words(row.reference), words(record.aavai.raw ?? '')),
      flowErrors: editDistance(words(row.reference), words(record.flow.raw ?? '')),
      referenceWords: words(row.reference).length });
  }
  if (errors.length) return { status: 'invalid', errors };
  const aggregate = subset => {
    const referenceWords = subset.reduce((s, x) => s + x.referenceWords, 0);
    return {
      count: subset.length,
      aavaiWER: subset.reduce((s, x) => s + x.aavaiErrors, 0) / referenceWords,
      flowWER: subset.reduce((s, x) => s + x.flowErrors, 0) / referenceWords,
      correctionEditDifference: subset.reduce((s, x) => s + x.difference, 0),
    };
  };
  return {
    // This report cannot promote a model: uncertainty and physical-device gates
    // require separate evidence. Never interpret WER as percent accuracy.
    status: scores.some(x => x.critical > 0) ? 'blocked-critical-meaning-errors' : 'review-required',
    overall: aggregate(scores), whisper: aggregate(scores.filter(x => x.whisper)),
    speakers: Object.fromEntries([...new Set(scores.map(x => x.speaker))].map(s => [s, aggregate(scores.filter(x => x.speaker === s))])),
    outstanding: ['paired speaker-level uncertainty', 'latency/memory/thermal gates', 'insertion safety and compatibility', 'offline network audit'],
  };
}
