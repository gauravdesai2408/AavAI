import test from "node:test";
import assert from "node:assert/strict";
import { deterministicCleanup, HttpError, UsageMeter, validateCleanupRequest } from "../src/core.mjs";

test("cleanup removes fillers and formats a sentence", () => {
  assert.equal(deterministicCleanup("um hello  there"), "Hello there.");
});

test("context is bounded", () => {
  const value = validateCleanupRequest({ transcript: "hello", context: { category: "generic", nearbyText: "x".repeat(900) }, dictionary: [] });
  assert.equal(value.context.nearbyText.length, 800);
});

test("invalid categories are rejected", () => {
  assert.throws(() => validateCleanupRequest({ transcript: "hello", context: { category: "secret" } }), HttpError);
});

test("usage quota rejects excess words", () => {
  const meter = new UsageMeter(3);
  meter.consume("a", 2);
  assert.throws(() => meter.consume("a", 2), /quota/);
});
