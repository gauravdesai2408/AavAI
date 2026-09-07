import { createServer } from "node:http";
import { HttpError, UsageMeter, validateCleanupRequest } from "./core.mjs";
import { createProvider } from "./providers.mjs";

const provider = createProvider();
const defaultLimit = process.env.AAVAI_PROVIDER === "local" ? Number.POSITIVE_INFINITY : 2_000;
const meter = new UsageMeter(Number(process.env.AAVAI_WEEKLY_WORD_LIMIT || defaultLimit));
const port = Number(process.env.PORT || 8787);

async function body(req, maximum = 10_000_000) {
  const chunks = []; let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > maximum) throw new HttpError(413, "request too large");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

function json(res, status, value) {
  const payload = JSON.stringify(value);
  res.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload), "Cache-Control": "no-store" });
  res.end(payload);
}

export function createApp() {
  return createServer(async (req, res) => {
    const requestId = crypto.randomUUID();
    try {
      if (req.method === "GET" && req.url === "/health") {
        const dependencies = provider.health ? await provider.health() : { provider: "development" };
        const ready = dependencies.whisper !== false && dependencies.ollama !== false;
        return json(res, ready ? 200 : 503, { status: ready ? "ok" : "degraded", dependencies, requestId });
      }
      if (req.method === "POST" && req.url === "/v1/transcribe") {
        const audio = await body(req);
        const dictionary = String(req.headers["x-dictionary"] || "").split(",").filter(Boolean).slice(0, 500);
        const text = await provider.transcribe(audio, { locale: req.headers["x-locale"] || "en", dictionary });
        meter.consume(req.headers.authorization || "local", text.trim().split(/\s+/).length);
        return json(res, 200, { text, requestId });
      }
      if (req.method === "POST" && req.url === "/v1/cleanup") {
        const input = validateCleanupRequest(JSON.parse((await body(req, 100_000)).toString("utf8")));
        return json(res, 200, { ...(await provider.cleanup(input)), requestId });
      }
      throw new HttpError(404, "not found");
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      // Never log audio, transcript, context, or dictionary contents.
      console.error(JSON.stringify({ level: "error", requestId, status, name: error.name, message: error.message }));
      json(res, status, { error: error.message, requestId });
    }
  });
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  createApp().listen(port, "127.0.0.1", () => console.log(`AavAI backend listening on http://127.0.0.1:${port}`));
}
