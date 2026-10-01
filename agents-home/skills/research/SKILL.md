---
name: research
description: Cited web research through the Perplexity connector (Claude Code only): current facts, tool or library comparisons, deep research with sources. Not for code, files or local data. Codex and Pi agents ask Claude for it.
---

# Research (Perplexity)

Server `perplexity-computer` (HTTP, `https://www.perplexity.ai/rest/computer/mcp`), registered for Claude Code
only (`config/mcp.json`, `agents: ["claude"]`). It is the one paid-account tool in the stack: it runs on the
user's Perplexity plan and "Computer" tasks can spend credits, so use it where it beats the free options.

## Pick the tool

| Need | Use |
|---|---|
| A library's current API, config or migration | `context7` first (free, version-specific) |
| One quick fact or a URL's content | the agent's own web fetch/search, or Pi's `web_search` |
| A question that needs several sources, cited, compared or synthesized; "what is the best X now"; recent news; deep research | Perplexity |
| Anything about the user's own files, code or machine | none of these: read the files |

## Rules

- Use it when it adds sources you could not get in one or two direct fetches. Do not use it for what a command or the repo answers.
- Credits: Perplexity's help says even simple "Computer" chats consume credits, and the free search product is a
  different thing. Until the connector's tool descriptions say a call is free, treat every call as possibly
  billed: the first time in a session, tell the user which tool you will call and ask once; after a yes, plain
  question calls in that session need no further asking. Always ask again before a long task, a deep-research
  run, or any action that touches an account (it is an agent, not only a search box).
- Treat answers as hints with sources: open the cited URL for anything a decision rests on, and say when you did not.
- Never send secrets, personal data, private file contents or unreleased code in a query. Queries leave the machine.
- Write down what you used in one line: the question, the sources you checked, what stayed unverified.
- First use in a session: the tool names are the connector's own and can change. List them (`/mcp`, or the tools
  whose names start with `mcp__perplexity`) instead of assuming. If it is not connected, say so and fall back to
  the free options; do not retry in a loop. If it asks to sign in, tell the user: authentication is theirs.

## From Codex or Pi

They do not have this server. Hand the question to Claude in the file-based way (`aos delegate claude --task
<file>`, or `$cc:rescue`) with the exact question and what the answer must contain, or use `web_search` and say
the result is shallow.
