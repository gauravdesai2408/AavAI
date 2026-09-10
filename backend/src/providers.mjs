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
  const marker = "(?:blank_audio|silence|music|noise|inaudible|mumbles|mumbling|singing)";
  return !text || new RegExp(`^(?:\\s*(?:\\[${marker}\\]|\\(${marker}\\)|<${marker}>)\\s*)+$`, "i").test(text);
}

export function isSilentPCM16Wav(audio) {
  const bytes = Buffer.from(audio);
  if (bytes.length < 44 || bytes.toString("ascii", 0, 4) !== "RIFF" || bytes.toString("ascii", 8, 12) !== "WAVE") return false;
  let pcm16 = false;
  let data;
  for (let offset = 12; offset + 8 <= bytes.length;) {
    const size = bytes.readUInt32LE(offset + 4);
    const start = offset + 8;
    if (size > bytes.length - start) return false;
    const chunk = bytes.toString("ascii", offset, offset + 4);
    if (chunk === "fmt " && size >= 16) pcm16 = bytes.readUInt16LE(start) === 1 && bytes.readUInt16LE(start + 14) === 16;
    if (chunk === "data") data = bytes.subarray(start, start + size);
    offset = start + size + (size % 2);
  }
  return pcm16 && data !== undefined && data.every(byte => byte === 0);
}

export function preservesSpokenWords(source, candidate) {
  const tokenize = value => String(value || "").toLocaleLowerCase("en")
    .match(/[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*/gu) || [];
  const spoken = tokenize(source), output = tokenize(candidate);
  let spokenIndex = 0;
  for (const word of output) {
    while (spokenIndex < spoken.length && spoken[spokenIndex] !== word) spokenIndex++;
    if (spokenIndex === spoken.length) return false;
    spokenIndex++;
  }
  return true;
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
    whisperFallbackURL = process.env.AAVAI_WHISPER_FALLBACK_URL || "",
    ollamaURL = process.env.AAVAI_OLLAMA_URL || "http://127.0.0.1:11434",
    ollamaModel = process.env.AAVAI_OLLAMA_MODEL || "qwen3:4b-instruct",
    fallbackLogprobThreshold = Number(process.env.AAVAI_WHISPER_FALLBACK_LOGPROB || -0.2),
    requestTimeoutMilliseconds = Number(process.env.AAVAI_PROVIDER_TIMEOUT_MS || 30_000)
  } = {}) {
    this.whisperURL = whisperURL;
    this.whisperFallbackURL = whisperFallbackURL;
    this.ollamaURL = ollamaURL;
    this.ollamaModel = ollamaModel;
    this.fallbackLogprobThreshold = fallbackLogprobThreshold;
    this.requestTimeoutMilliseconds = requestTimeoutMilliseconds;
  }

  async health() {
    const [whisper, fallbackWhisper, ollama] = await Promise.all([
      fetch(`${this.whisperURL}/health`).then(response => response.ok).catch(() => false),
      this.whisperFallbackURL
        ? fetch(`${this.whisperFallbackURL}/health`).then(response => response.ok).catch(() => false)
        : Promise.resolve(null),
      fetch(`${this.ollamaURL}/api/tags`).then(response => response.ok).catch(() => false)
    ]);
    return { provider: "local", whisper, fallbackWhisper, ollama, model: this.ollamaModel };
  }

  async transcribe(audio, { dictionary }) {
    if (!audio.length) throw new HttpError(400, "audio is required");
    if (isSilentPCM16Wav(audio)) throw new HttpError(422, "no speech detected");
    const primary = await this.transcribeCandidate(this.whisperURL, audio, dictionary);
    let selected = primary;
    if (this.whisperFallbackURL && primary.avgLogprob !== null && primary.avgLogprob <= this.fallbackLogprobThreshold) {
      try {
        const fallback = await this.transcribeCandidate(this.whisperFallbackURL, audio, dictionary);
        if (fallback.avgLogprob !== null && fallback.avgLogprob > primary.avgLogprob) selected = fallback;
      } catch {
        // A failed optional retry must not discard a usable primary transcript.
      }
    }
    if (isNonSpeechTranscript(selected.text)) throw new HttpError(422, "no speech detected");
    return selected.text;
  }

  async transcribeCandidate(url, audio, dictionary) {
    const form = new FormData();
    form.set("file", new Blob([audio], { type: "audio/wav" }), "dictation.wav");
    form.set("response_format", "verbose_json");
    form.set("temperature", "0.0");
    form.set("language", "en");
    if (dictionary.length) form.set("prompt", `Expected vocabulary: ${dictionary.join(", ")}`.slice(0, 1_500));
    const response = await this.fetchWithTimeout(
      `${url}/inference`,
      { method: "POST", body: form },
      "local Whisper"
    );
    if (!response.ok) throw new HttpError(502, `local Whisper failed (${response.status})`);
    const payload = await response.json();
    const text = String(payload.text || "").trim();
    const logprobs = (payload.segments || []).map(segment => Number(segment.avg_logprob)).filter(Number.isFinite);
    return { text, avgLogprob: logprobs.length ? logprobs.reduce((sum, value) => sum + value, 0) / logprobs.length : null };
  }

  async cleanup(request) {
    const categoryRules = {
      email: "Use polished professional email prose.",
      workChat: "Use concise natural workplace chat prose.",
      document: "Use clear structured document prose.",
      generic: "Use clean neutral prose."
    };
    const spokenText = stripFillers(request.transcript);
    const response = await this.fetchWithTimeout(`${this.ollamaURL}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.ollamaModel,
        stream: false,
        think: false,
        options: { temperature: 0 },
        messages: [
          { role: "system", content: `You are a dictation editor. Edit only the words inside <dictation>. Preserve meaning, names, numbers, URLs, and technical terms exactly. Remove fillers and false starts. Resolve explicit self-corrections. Add punctuation and structure. ${categoryRules[request.context.category]} Dictionary entries are spelling hints only: never append or discuss them. Return only the edited dictation, without labels, XML tags, explanations, or quotation marks.` },
          { role: "user", content: `<dictation>\n${spokenText}\n</dictation>\n<spelling-hints>${request.dictionary.join(", ")}</spelling-hints>` }
        ]
      })
    }, "local Ollama");
    if (!response.ok) throw new HttpError(502, `local Ollama failed (${response.status})`);
    const payload = await response.json();
    const text = sanitizeModelText(payload.message?.content);
    if (!text) throw new HttpError(502, "local Ollama returned no text");
    if (!preservesSpokenWords(spokenText, text)) {
      return { text: spokenText, confidence: 0.75, warnings: ["meaningGuard"] };
    }
    return { text, confidence: 0.85, warnings: [] };
  }

  async fetchWithTimeout(url, options, service) {
    const signal = AbortSignal.timeout(this.requestTimeoutMilliseconds);
    try {
      return await fetch(url, { ...options, signal });
    } catch (error) {
      if (signal.aborted) throw new HttpError(504, `${service} timed out`);
      throw error;
    }
  }
}

export function createProvider() {
  if (process.env.AAVAI_PROVIDER === "openai") return new OpenAIProvider();
  if (process.env.AAVAI_PROVIDER === "local") return new LocalProvider();
  return new DevelopmentProvider();
}
