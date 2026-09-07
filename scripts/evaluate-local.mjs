const baseURL = process.env.AAVAI_EVAL_URL || "http://127.0.0.1:8787";

const cases = [
  {
    name: "fillers and name",
    transcript: "um hey Sarah uh can we move the meeting to 3:30 tomorrow",
    category: "workChat",
    must: [/Sarah/i, /3:30/, /tomorrow/i],
    mustNot: [/\bum\b/i, /\buh\b/i]
  },
  {
    name: "spoken correction",
    transcript: "Send it on Tuesday, no sorry, send it on Thursday.",
    category: "workChat",
    must: [/Thursday/i],
    mustNot: [/Tuesday/i, /no sorry/i]
  },
  {
    name: "number preservation",
    transcript: "The invoice total is 1,247 dollars and 83 cents.",
    category: "email",
    must: [/1[,.]?247/, /83/],
    mustNot: []
  },
  {
    name: "literal URL preservation",
    transcript: "The documentation is at https://example.com/api/v2.",
    category: "document",
    must: [/https:\/\/example\.com\/api\/v2/],
    mustNot: []
  },
  {
    name: "technical terms and dictionary",
    transcript: "Deploy AavAI with PostgreSQL and Kubernetes.",
    category: "document",
    dictionary: ["AavAI", "PostgreSQL", "Kubernetes"],
    must: [/AavAI/, /PostgreSQL/, /Kubernetes/],
    mustNot: [/dictionary:/i, /spelling-hints/i]
  },
  {
    name: "list structure",
    transcript: "The priorities are first fix onboarding second reduce latency and third test Slack insertion.",
    category: "document",
    must: [/onboarding/i, /latency/i, /Slack/i],
    mustNot: []
  }
];

let failures = 0;
for (const item of cases) {
  const response = await fetch(`${baseURL}/v1/cleanup`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      transcript: item.transcript,
      context: { bundleIdentifier: null, applicationName: "Evaluation", category: item.category, nearbyText: "", isSecure: false },
      locale: "en",
      dictionary: item.dictionary || []
    })
  });
  const payload = await response.json();
  const text = String(payload.text || "");
  const missing = item.must.filter(pattern => !pattern.test(text));
  const forbidden = item.mustNot.filter(pattern => pattern.test(text));
  const passed = response.ok && missing.length === 0 && forbidden.length === 0 && text.length > 0;
  if (!passed) failures += 1;
  console.log(`${passed ? "PASS" : "FAIL"} ${item.name}: ${JSON.stringify(text)}`);
}

console.log(`\n${cases.length - failures}/${cases.length} local cleanup evaluations passed.`);
if (failures) process.exit(1);
