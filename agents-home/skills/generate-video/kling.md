# Kling recipe

**Operator decision, 2026-11-14:** drive Kling in the browser like the other platforms. Kling's terms
(kling.ai/docs/user-policy, updated 2026-04-21, read 2026-11-13), section 3.1(h), say users may not "use automated
scripts to collect information from or otherwise interact with the Services"; the operator accepts the risk to the
account (a suspension) and asked for it to be driven anyway. Limits that stay: human pace, one take at a time, never
solve a CAPTCHA, never work around a credit cap or rate limit, stop and report when the page blocks or warns.
Section 4.6 restricts use of Output without written permission: record `--commercial no`. Kling lives at kling.ai
(it was app.klingai.com on 2026-11-12).

## Steps (from the 2026-11-12 spike; re-verify each on the page)

- The page is wider than a narrow pane: emulate a 1440x900 viewport and prefer page scripts over coordinates.
- Credits sit in the left rail (66 on a fresh free account). The generate button shows the cost: the flagship model
  50 credits for a 720p 5 s take, the fast one 30.
- Generate, then the reference-mode dropdown in the prompt bar (default "Omni reference"): **Keyframes**. First frame
  and Last frame slots appear.
- First frame: set the slot's own `input[type=file]` (single file, .jpg/.png) with a `File` built in the page (SKILL.md,
  local files). Last frame: a drop on the strip adds a Middle frame instead; click the Last frame tile, choose Upload,
  and fill the file input that Upload opens.
- Type the prompt, press Generate. The free queue said about 4 minutes and took about that; an end frame makes it slower.
- File link: the tiles play `blob:` links; the real link is in the page's `projects-assets/batch-status` response,
  `works[].resource.resource` (an `.mp4` on Kling's CDN). Fetch it with `aos asset fetch --platform kling
  --watermark yes --commercial no`.
- Output: 1280x720, 24 fps, 5 s, audio track, a visible "KlingAI" watermark on the free plan (keep it).
- Behaviour seen: particles moved into the end keyframe (reached, not faded in); a disc looked stiff and the motion
  started within 3 frames.

## By hand, when the operator prefers

Put the two keyframes (1280x720 PNG) and a PROMPT-SHEET.md in the film's `generated/kling/` (mode, files, 16:9, 720p,
5 s, model, prompt, where to save the mp4 with its watermark).
