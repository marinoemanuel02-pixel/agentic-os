// Small, read-only web search tool for the local Pi agent. The permission gate still asks before
// every call because network access is an external operation. Search results include source URLs;
// this is not a browser and does not grant the agent arbitrary page or computer access.

type SearchResult = { title: string; url: string; snippet: string };
type FetchLike = (input: string, init?: Record<string, unknown>) => Promise<{
  ok: boolean;
  status: number;
  text(): Promise<string>;
}>;

function decodeHtml(value: string): string {
  return value.replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#x2F;/gi, "/");
}

function normalizeResultUrl(raw: string): string {
  const url = decodeHtml(raw).trim();
  try {
    const parsed = new URL(url);
    const encoded = parsed.searchParams.get("u");
    if (encoded?.startsWith("a1")) {
      const payload = encoded.slice(2).replace(/-/g, "+").replace(/_/g, "/");
      return Buffer.from(payload + "=".repeat((4 - payload.length % 4) % 4), "base64").toString("utf8");
    }
  } catch { /* Keep the original source URL when a result is unusual. */ }
  return url;
}

export function parseBingResults(html: string, limit = 5): SearchResult[] {
  const results: SearchResult[] = [];
  const itemPattern = /<li class="b_algo"[\s\S]*?<h2[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>\s*<\/h2>([\s\S]*?)<\/li>/gi;
  for (const match of html.matchAll(itemPattern)) {
    const url = normalizeResultUrl(match[1]);
    const title = decodeHtml(match[2].replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim();
    const paragraph = /<p[^>]*>([\s\S]*?)<\/p>/i.exec(match[3])?.[1] ?? match[3];
    const body = paragraph.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    if (url && title) results.push({ title, url, snippet: decodeHtml(body).slice(0, 500) });
    if (results.length >= limit) break;
  }
  return results;
}

export async function searchWeb(query: string, fetchImpl: FetchLike = fetch, signal?: AbortSignal): Promise<SearchResult[]> {
  const clean = query.trim();
  if (!clean || clean.length > 240) throw new Error("web_search query must be 1-240 characters");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const response = await fetchImpl(`https://www.bing.com/search?q=${encodeURIComponent(clean)}`, {
      headers: { "user-agent": "agentic-os local search/1" }, signal: signal ?? controller.signal,
    });
    if (!response.ok) throw new Error(`Search provider returned HTTP ${response.status}`);
    const html = await response.text();
    return parseBingResults(html);
  } finally { clearTimeout(timeout); }
}

export default function register(pi: { registerTool(tool: Record<string, unknown>): void }) {
  pi.registerTool({
    name: "web_search",
    label: "Web search",
    description: "Search the public web and return a few results with source URLs. This is not a browser.",
    parameters: { type: "object", properties: { query: { type: "string", description: "A concise web search query" } }, required: ["query"], additionalProperties: false },
    async execute(_toolCallId: string, params: { query: string }, signal: AbortSignal) {
      try {
        const results = await searchWeb(params.query, fetch, signal);
        if (!results.length) return { content: [{ type: "text", text: "No search results were returned." }] };
        return { content: [{ type: "text", text: results.map((r, i) => `${i + 1}. ${r.title}\n${r.url}\n${r.snippet}`).join("\n\n") }], details: { results } };
      } catch (error) {
        return { content: [{ type: "text", text: `Web search failed: ${error instanceof Error ? error.message : String(error)}` }] };
      }
    },
  });
}
