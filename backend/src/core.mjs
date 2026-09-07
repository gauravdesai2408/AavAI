const APP_CATEGORIES = new Set(["email", "workChat", "document", "generic"]);

export function validateCleanupRequest(value) {
  if (!value || typeof value.transcript !== "string" || value.transcript.length === 0) {
    throw new HttpError(400, "transcript is required");
  }
  if (value.transcript.length > 30_000) throw new HttpError(413, "transcript is too long");
  if (!value.context || !APP_CATEGORIES.has(value.context.category)) throw new HttpError(400, "invalid context category");
  value.context.nearbyText = String(value.context.nearbyText ?? "").slice(-800);
  value.dictionary = Array.isArray(value.dictionary) ? value.dictionary.slice(0, 500).map(String) : [];
  return value;
}

export function deterministicCleanup(input) {
  let text = input.trim()
    .replace(/\b(um+|uh+|you know)\b[,.]?\s*/gi, "")
    .replace(/\s+([,.!?])/g, "$1")
    .replace(/\s{2,}/g, " ");
  text = text.charAt(0).toUpperCase() + text.slice(1);
  if (text && !/[.!?]$/.test(text)) text += ".";
  return text;
}

export class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export class UsageMeter {
  #counts = new Map();
  constructor(limit = 2_000) { this.limit = limit; }
  consume(accountId, words) {
    const current = this.#counts.get(accountId) ?? 0;
    if (current + words > this.limit) throw new HttpError(429, "weekly quota exceeded");
    this.#counts.set(accountId, current + words);
    return { used: current + words, limit: this.limit };
  }
}
