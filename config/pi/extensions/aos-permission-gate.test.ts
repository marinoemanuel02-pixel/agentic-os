// Unit tests for the aos permission gate: `node --experimental-strip-types --test <this file>`
// (aos test runs it). Pi executes a tool only when every tool_call handler lets it through.
import { test } from "node:test";
import assert from "node:assert/strict";
import gate from "./aos-permission-gate.ts";

type Handler = (event: { toolName: string; input: unknown }, ctx: unknown) => Promise<unknown>;

function loadHandler(): Handler {
  let handler: Handler | undefined;
  gate({ on: (name: string, fn: Handler) => { if (name === "tool_call") handler = fn; } } as never);
  assert.ok(handler, "the gate registers a tool_call handler");
  return handler;
}

function fakeCtx(answer: string | undefined, hasUI = true) {
  const asked: string[] = [];
  return { asked, ctx: { hasUI, ui: { select: async (title: string) => { asked.push(title); return answer; } } } };
}

const gated: Array<[string, Record<string, unknown>, string]> = [
  ["bash", { command: "rm -r build" }, "rm -r build"],
  ["write", { path: "notes.txt", content: "x" }, "notes.txt"],
  ["edit", { path: "src/a.ts", oldText: "a", newText: "b" }, "src/a.ts"],
  ["some_extension_tool", { anything: 1 }, "some_extension_tool"],
  ["web_search", { query: "Ollama documentation" }, "Ollama documentation"],
];

for (const [tool, input, shown] of gated) {
  test(`${tool}: runs only after Allow, and the question names it`, async () => {
    const { asked, ctx } = fakeCtx("Allow");
    assert.equal(await loadHandler()({ toolName: tool, input }, ctx), undefined);
    assert.equal(asked.length, 1);
    assert.ok(asked[0].includes(shown), asked[0]);
  });

  test(`${tool}: Deny blocks it, with a reason a small model cannot read as success`, async () => {
    // Measured 2026-09-29: qwen3.5:4b read "Denied by the user" as the command's output and claimed success.
    const { ctx } = fakeCtx("Deny");
    const result = (await loadHandler()({ toolName: tool, input }, ctx)) as { block?: boolean; reason?: string };
    assert.equal(result?.block, true);
    assert.match(result?.reason ?? "", /^NOT RUN\b/);
    assert.match(result?.reason ?? "", /nothing was executed/i);
  });

  test(`${tool}: a dismissed dialog blocks it`, async () => {
    const { ctx } = fakeCtx(undefined);
    const result = (await loadHandler()({ toolName: tool, input }, ctx)) as { block?: boolean };
    assert.equal(result?.block, true);
  });

  test(`${tool}: without a UI it is blocked and nobody is asked`, async () => {
    const { asked, ctx } = fakeCtx("Allow", false);
    const result = (await loadHandler()({ toolName: tool, input }, ctx)) as { block?: boolean };
    assert.equal(result?.block, true);
    assert.equal(asked.length, 0);
  });
}

for (const tool of ["read", "grep", "find", "ls"]) {
  test(`${tool} is read-only and runs without a question`, async () => {
    const { asked, ctx } = fakeCtx("Deny");
    assert.equal(await loadHandler()({ toolName: tool, input: { path: "." } }, ctx), undefined);
    assert.equal(asked.length, 0);
  });
}

test("a missing input still produces a question", async () => {
  const { asked, ctx } = fakeCtx("Allow");
  assert.equal(await loadHandler()({ toolName: "bash", input: undefined }, ctx), undefined);
  assert.equal(asked.length, 1);
});
