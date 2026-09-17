import { readFile } from 'node:fs/promises';
import { validateCorpus, corpusDigest, compareFinal } from './protocol.mjs';

const [manifestPath, runPath] = process.argv.slice(2);
if (!manifestPath) throw new Error('Usage: node scripts/evaluation/report.mjs manifest.json [paired-run.json]');
const corpus = JSON.parse(await readFile(manifestPath, 'utf8'));
const result = runPath
  ? compareFinal(corpus, JSON.parse(await readFile(runPath, 'utf8')))
  : { errors: validateCorpus(corpus), corpusSHA256: corpusDigest(corpus) };
console.log(JSON.stringify(result, null, 2));
if (result.errors?.length || result.status === 'blocked-critical-meaning-errors') process.exitCode = 1;
