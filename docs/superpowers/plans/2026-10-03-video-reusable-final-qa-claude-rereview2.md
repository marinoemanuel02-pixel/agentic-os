# Claude second bounded template re-review

Receipt: 20261003-163227-350d-claude-independent-bounded-read-only. Accepted read-only result; separate verdict.

VERDICT: REVISE (Claude's verdict only, separate from Codex's). One small but concrete blocker remains.

RESOLVED: I reproduced all four earlier probes with the real extract(). Each now returns the expected words with no errors: Outer/inner/tail; Up to/40%/faster; `style={{... f > 10 ...}}` gives Hidden words; `at={() => 3}` gives Arrow child. Text inside nested conditionals (`{show ? <Reveal>Shown</Reveal> : null}`) is collected. `<b>{percent}</b>`, `{t("key")}` and template text with `${}` all fail as computed text.

REMAINING BLOCKER (medium): templates/video/tools/checks/screen-text.mjs:69. `new RegExp(`^${STR}$`)` leaves the alternation ungrouped. So `^` applies only to the double-quote branch and `$` only to the backtick branch, and the single-quote branch can match anywhere in the value. My probes:
- `<Reveal>{done ? 'Ready' : 'Waiting'}</Reveal>` gives the text `one ? 'Ready' : 'Waiting` and no error.
- `<p>{n + '%'}</p>` gives ` + '%` and no error.
- `<Reveal>{"Up " + pct}</Reveal>` makes JSON.parse throw. The gate crashes with a stack trace instead of printing FAIL lines.
Coverage still rejects the junk strings, because they aren't in claims.json. But the 'computed screen text' error never fires. An author, or an agent fixing the gate, can paste the junk string into the ledger to make it pass. Then 'Ready'/'Waiting' reach the screen without a reviewed entry. A ternary as a JSX child is idiomatic, so this is a real path around the gate. Fix: `^(?:${STR})$`, plus a fixture for a ternary child and one for a concatenated child.

NON-BLOCKING LIMITS (seen in probes):
- At the top level of a file, a regex literal holding a quote (`const re = /'/;`) makes the scanner skip the JSX after it. `<Reveal>Behind regex</Reveal>` came back [] with no errors. That fails open, but it's rare in shot files.
- An apostrophe in JSX text inside a `{...}` child, or a `//` comment holding an apostrophe inside braces, drops the words after it. But the scanner reports 'unclosed JSX children', so it fails closed.
- `a<b && c>d` with no spaces, in a file that also contains `</b>`, produces junk text plus an error. Fails closed.
- `{items.map(...)}` directly under a div/p is rejected as computed text. A false positive, fails closed.
- `<Text>{title}</Text>` and `<AbsoluteFill>{title}</AbsoluteFill>` pass silently. That matches the documented 'custom dynamic text unsupported' convention (R24 and the template AGENTS.md), so it isn't a blocker.

The balanced quote/brace scanning, the nesting stack and the root-needs-a-closing-tag rule look sound for the documented conventions, apart from line 69. Final pixel review stays mandatory.

