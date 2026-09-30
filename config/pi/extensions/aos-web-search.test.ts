import { test } from "node:test";
import assert from "node:assert/strict";
import { parseBingResults, searchWeb } from "./aos-web-search.ts";

test("parses Bing result titles, URLs and snippets", () => {
  const results = parseBingResults('<li class="b_algo"><h2><a href="https://example.com/?a=1&amp;b=2">Example <strong>title</strong></a></h2><p>A useful snippet.</p></li>');
  assert.deepEqual(results, [{ title: "Example title", url: "https://example.com/?a=1&b=2", snippet: "A useful snippet." }]);
});

test("unwraps Bing redirect URLs and current result markup", () => {
  const results = parseBingResults('<li class="b_algo" data-id="x"><h2 class=""><a target="_blank" href="https://www.bing.com/ck/a?!&amp;u=a1aHR0cHM6Ly9vbGxhbWEuY29tLw&amp;ntb=1"><strong>Ollama</strong></a></h2><div class="b_caption"><p class="b_lineclamp2">Official docs.</p></div></li>');
  assert.deepEqual(results[0], { title: "Ollama", url: "https://ollama.com/", snippet: "Official docs." });
});

test("searchWeb validates the query and sends a bounded request", async () => {
  let request = "";
  const results = await searchWeb("local models", async (input) => {
    request = input;
    return { ok: true, status: 200, text: async () => '<li class="b_algo"><h2><a href="https://example.test">Result</a></h2><p>Snippet</p></li>' };
  });
  assert.equal(request, "https://www.bing.com/search?q=local%20models");
  assert.equal(results[0]?.url, "https://example.test");
  await assert.rejects(() => searchWeb("   ", async () => { throw new Error("must not fetch"); }), /1-240/);
});
