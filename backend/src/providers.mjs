import { deterministicCleanup, HttpError } from "./core.mjs";

export function sanitizeModelText(value) {
  let text = String(value || "").trim();
  text = text.replace(/^```(?:text)?\s*/i, "").replace(/\s*```$/, "").trim();
  if ((text.startsWith('"') && text.endsWith('"')) || (text.startsWith("“") && text.endsWith("”"))) {
    text = text.slice(1, -1).trim();
  }
  text = text
    .split(/\r?\n/)
    .filter(line => !/^\s*(nearby text|dictionary|category|context)\s*:/i.test(line)
      && !/^\s*<\/?(?:dictation|spelling-hints)>\s*$/i.test(line))
    .join("\n")
    .trim();
  return stripFillers(text);
}

export function stripFillers(value) {
  return String(value || "")
    .replace(/\b(?:um+|uh+|erm+|hmm+|you know)\b[,.]?\s*/gi, "")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

export function isNonSpeechTranscript(value) {
  const text = String(value || "").trim().toLowerCase();
  return !text
    || /^\[(?:blank_audio|silence|music|noise|inaudible)\]$/i.test(text)
    || /^\((?:silence|music|noise|inaudible)\)$/i.test(text)
    || /^<(?:silence|music|noise|inaudible)>$/i.test(text);
}

export class DevelopmentProvider {
  async transcribe(audio) {
    if (!audio.length) throw new HttpError(400, "audio is required");
    return process.env.AAVAI_DEMO_TRANSCRIPT || "This is a local development transcription";
  }
  async cleanup(request) {
    return { text: deterministicCleanup(request.transcript), confidence: 0.75, warnings: ["developmentProvider"] };
  }
}

export class OpenAIProvider {
  constructor(apiKey = process.env.OPENAI_API_KEY) {
    if (!apiKey) throw new Error("OPENAI_API_KEY is required when AAVAI_PROVIDER=openai");
    this.apiKey = apiKey;
  }
  async transcribe(audio, { locale, dictionary }) {
    const form = new FormData();
    form.set("file", new Blob([audio], { type: "audio/wav" }), "dictation.wav");
    form.set("model", process.env.AAVAI_TRANSCRIPTION_MODEL || "gpt-4o-mini-transcribe");
    form.set("language", locale || "en");
    form.set("prompt", `Expected vocabulary: ${dictionary.join(", ")}`.slice(0, 1_500));
    const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST", headers: { Authorization: `Bearer ${this.apiKey}` }, body: form
    });
    if (!response.ok) throw new HttpError(502, "transcription provider failed");
    return (await response.json()).text;
  }
  async cleanup(request) {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { Authorization: `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: process.env.AAVAI_CLEANUP_MODEL || "gpt-4.1-mini",
        input: [
          { role: "system", content: "Polish dictated text. Preserve meaning, names, numbers, URLs, and technical terms. Remove fillers and false starts. Resolve explicit self-corrections. Add appropriate punctuation and structure. Return only the polished text." },
          { role: "user", content: JSON.stringify({ transcript: request.transcript, category: request.context.category, nearbyText: request.context.nearbyText, dictionary: request.dictionary }) }
        ]
      })
    });
    if (!response.ok) throw new HttpError(502, "cleanup provider failed");
    const payload = await response.json();
    const text = payload.output_text || payload.output?.flatMap(item => item.content ?? []).find(item => item.type === "output_text")?.text;
    if (!text) throw new HttpError(502, "cleanup provider returned no text");
    return { text, confidence: 0.9, warnings: [] };
  }
}

export class LocalProvider {
  constructor({
    whisperURL = process.env.AAVAI_WHISPER_URL || "http://127.0.0.1:8080",
    ollamaURL = process.env.AAVAI_OLLAMA_URL || "http://127.0.0.1:11434",
    ollamaModel = process.env.AAVAI_OLLAMA_MODEL || "qwen3:4b-instruct"
  } = {}) {
    this.whisperURL = whisperURL;
    this.ollamaURL = ollamaURL;
    this.ollamaModel = ollamaModel;
  }

  async health() {
    const [whisper, ollama] = await Promise.all([
      fetch(`${this.whisperURL}/health`).then(response => response.ok).catch(() => false),
      fetch(`${this.ollamaURL}/api/tags`).then(response => response.ok).catch(() => false)
    ]);
    return { provider: "local", whisper, ollama, model: this.ollamaModel };
  }

  async transcribe(audio, { dictionary }) {
    if (!audio.length) throw new HttpError(400, "audio is required");
    const form = new FormData();
    form.set("file", new Blob([audio], { type: "audio/wav" }), "dictation.wav");
    form.set("response_format", "json");
    form.set("temperature", "0.0");
    if (dictionary.length) form.set("prompt", `Expected vocabulary: ${dictionary.join(", ")}`.slice(0, 1_500));
    const response = await fetch(`${this.whisperURL}/inference`, { method: "POST", body: form });
    if (!response.ok) throw new HttpError(502, `local Whisper failed (${response.status})`);
    const payload = await response.json();
    const text = String(payload.text || "").trim();
    if (isNonSpeechTranscript(text)) throw new HttpError(422, "no speech detected");
    return text;
  }

  async cleanup(request) {
    const categoryRules = {
      email: "Use polished professional email prose.",
      workChat: "Use concise natural workplace chat prose.",
      document: "Use clear structured document prose.",
      generic: "Use clean neutral prose."
    };
    const response = await fetch(`${this.ollamaURL}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.ollamaModel,
        stream: false,
        think: false,
        options: { temperature: 0 },
        messages: [
          { role: "system", content: `You are a dictation editor. Edit only the words inside <dictation>. Preserve meaning, names, numbers, URLs, and technical terms exactly. Remove fillers and false starts. Resolve explicit self-corrections. Add punctuation and structure. ${categoryRules[request.context.category]} Dictionary entries are spelling hints only: never append or discuss them. Return only the edited dictation, without labels, XML tags, explanations, or quotation marks.` },
          { role: "user", content: `<dictation>\n${stripFillers(request.transcript)}\n</dictation>\n<spelling-hints>${request.dictionary.join(", ")}</spelling-hints>` }
        ]
      })
    });
    if (!response.ok) throw new HttpError(502, `local Ollama failed (${response.status})`);
    const payload = await response.json();
    const text = sanitizeModelText(payload.message?.content);
    if (!text) throw new HttpError(502, "local Ollama returned no text");
    return { text, confidence: 0.85, warnings: [] };
  }
}

export function createProvider() {
  if (process.env.AAVAI_PROVIDER === "openai") return new OpenAIProvider();
  if (process.env.AAVAI_PROVIDER === "local") return new LocalProvider();
  return new DevelopmentProvider();
}
