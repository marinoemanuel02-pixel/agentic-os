# Kling recipe

Last verified 2026-11-12 (one spike, English UI). The page is wider than a narrow browser pane: emulate a
1440x900 viewport or collapse the side panel, and prefer page scripts over coordinates.

## Observed

- **Credits:** shown in the left rail (66 on a fresh free account).
- **Frames mode:** Generate, then the reference-mode dropdown in the prompt bar (default "Omni reference"):
  Keyframes. First frame and Last frame slots appear.
- **Model and cost:** the generate button shows the cost. The flagship model cost 50 credits for a 720p 5 s take,
  the fast model 30. Only one flagship take fits a day's free credits.
- **First frame:** setting the slot's own file input (`input[type=file]`, single file, .jpg/.png) worked.
- **Last frame:** a drop on the strip adds a Middle frame instead. Click the Last frame tile, choose Upload, and fill
  the file input that Upload opens. No rights dialog appeared.
- **Generate:** type the prompt in the prompt box, press Generate. The free queue said "about 4 minutes" and took
  about that; using an end frame makes it slower, the page says.
- **File link:** the tiles play `blob:` links. The real link is in the page's own `projects-assets/batch-status`
  response, `works[].resource.resource` (an `.mp4` on Kling's CDN). Pass it to `aos asset fetch --url`.
- **Output:** 1280x720, 24 fps, 5 s, audio track, a visible "KlingAI" watermark in the corner on the free plan.
- **Behaviour:** particles moved into the end keyframe (it is reached, not faded in); the disc stage looked stiff
  and the burst started within 3 frames.

## Secondhand, check first-hand

- Free output is non-commercial and must keep its watermark (several reviews citing Kling's terms, section 4.6):
  record `--commercial no` and `--watermark yes` unless the terms read first-hand say otherwise.
- Automated use: Kling's terms not yet read.
