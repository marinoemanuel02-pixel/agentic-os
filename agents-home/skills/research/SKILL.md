---
name: research
description: Cited web research with each agent's own free tools (Claude's web search and fetch, Codex's web search, Pi's web_search): current facts, comparisons, news, every claim traced to a page that was opened. Not for code or local files.
---

# Research (free web tools)

There is no paid research service in this setup. Perplexity's connector was removed on 2026-10-01: its only
working tool ("Computer") needs bought credits, which the free-stack rule does not allow (see
`docs/decisions.md`).

## Pick the tool

| Need | Use |
|---|---|
| A library's current API, config or migration | `context7` first (free, version-specific) |
| Current facts, comparisons, news, several sources | Claude Code: `WebSearch` to find pages, `WebFetch` to open and read them. Codex: its web search. Pi: `web_search` (shallow; say so) |
| Pages that block fetching (403, 451, logins) | the built-in browser (`get_page_text`), or another source for the same fact |
| Anything about the user's own files, code or machine | none of these: read the files |

## Method

1. Search with dated, specific queries ("... September 2026"); prefer primary sources (the company, the agency,
   the paper) over aggregators and SEO summaries.
2. Open the page for every claim a decision or a script rests on. A search-result summary is a lead, not a
   source: summaries here have been wrong on dates and numbers.
3. Write each claim with its URL, date and how it was checked ("opened" vs "snippet only"). When sources
   disagree, keep both and say which one you used.
4. Unknown stays unknown: if no page you opened supports it, leave the claim out.
5. Never put secrets, personal data, private file contents or unreleased code in a query.

## From Codex or Pi

Both have web search of their own. For research that needs many fetched pages and careful citation, hand the
question to Claude with `aos delegate claude --task <file>` or `$cc:rescue`, saying exactly what the answer must
contain.
