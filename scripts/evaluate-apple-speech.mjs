import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

const baseline = JSON.parse(await readFile('.evaluation/cstr/confidence-turbo.json', 'utf8'));
const temporary = await mkdtemp('/private/tmp/aavai-apple-results-');
const tokens = text => text.toLowerCase().replace(/[^a-z0-9'\s]/g, ' ').split(/\s+/).filter(Boolean);
function distance(a, b) {
  let row = Array.from({length:b.length+1}, (_, i) => i);
  for (let i=1; i<=a.length; i++) {
    const next=[i];
    for (let j=1; j<=b.length; j++) next[j]=Math.min(next[j-1]+1,row[j]+1,row[j-1]+Number(a[i-1]!==b[j-1]));
    row=next;
  }
  return row[b.length];
}
const results=[];
try {
  for (const sample of baseline.results) {
    const stdout=join(temporary, `output-${results.length}`), stderr=join(temporary, `error-${results.length}`);
    await writeFile(stdout, ''); await writeFile(stderr, '');
    const sourceAudio=join(process.cwd(), '.evaluation/cstr/CSTR-NAM-TIMIT-Plus', sample.condition, sample.name);
    const audio=join(temporary, `audio-${results.length}.wav`);
    execFileSync('/usr/bin/afconvert',['-f','WAVE','-d','LEI16@16000','-c','1',sourceAudio,audio]);
    const started=performance.now();
    execFileSync('/usr/bin/open', ['-n','-W','--stdout',stdout,'--stderr',stderr,'/private/tmp/AavAI Speech Evaluation.app','--args',audio], {timeout:75000});
    const text=(await readFile(stdout,'utf8')).trim(), error=(await readFile(stderr,'utf8')).trim();
    const result={condition:sample.condition,name:sample.name,reference:sample.reference,text,error,words:tokens(sample.reference).length,wordErrors:distance(tokens(sample.reference),tokens(text)),milliseconds:Math.round(performance.now()-started)};
    results.push(result); console.log(JSON.stringify(result));
    await writeFile('.evaluation/cstr/apple-speech.json',JSON.stringify({complete:false,results},null,2));
  }
  const summary={samples:results.length,failures:results.filter(x=>x.error || !x.text).length,words:results.reduce((s,x)=>s+x.words,0),errors:results.reduce((s,x)=>s+x.wordErrors,0)};
  summary.wordErrorRate=summary.errors/summary.words;
  await writeFile('.evaluation/cstr/apple-speech.json',JSON.stringify({complete:true,summary,results},null,2));
  console.log(JSON.stringify(summary));
} finally { await rm(temporary,{recursive:true,force:true}); }
