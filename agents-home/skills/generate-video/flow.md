# Google Flow recipe

Last verified 2026-11-12 (one spike, account UI in Italian; labels follow the account language).

## Observed

- **Start:** the Flow home page, New project. An announcement dialog may open first; it only needs dismissing.
- **Frames mode:** the prompt bar's mode chip: Video, then Frames. Start and End slots appear above the prompt.
  Set 16:9 or 9:16 and the take count (x1-x4) in the same menu; it shows the credit cost before generating.
- **Model:** pick the cheapest model in the list that supports frames; its cost was 10 credits per take
  (x2 = 20 credits). Some models in the list carried an end-of-availability date.
- **Upload:** a drop event with the image files on the project's media area (the "drag media here" area) worked;
  the built-in browser could not use the file picker. The files were built in the page (canvas redraws of the
  keyframes), not local PNGs: see SKILL.md, local files. The first upload opens an image-rights confirmation: the
  operator's OK.
- **Slots:** click Start, pick the uploaded image from the project's media list; same for End.
- **Generate:** type the prompt, press the generate arrow. Two takes took about 1.5 minutes.
- **File link:** open the take (its page is `/project/<id>/edit/<id>`); `document.querySelector('video').currentSrc`
  is a signed link with an expiry in its query (lifetime not measured; fetch it soon). Pass it to
  `aos asset fetch --url`.
- **Output:** 1280x720, 24 fps, 7.9 s, with an audio track (drop it unless the shot needs it).
- **Behaviour:** the end keyframe's geometry is matched exactly, slightly darker; the target faded in instead of
  being reached by the motion, then held still about 2.5 s.
- **Watermark:** none visible.

## Secondhand, check first-hand

- Free allowance: 50 credits a day, no rollover (Google's Flow help page, read through search, not on the page).
- Ownership: Google says it does not claim ownership of generated content. No official statement found that
  free-credit output may be used commercially: record `--commercial unknown` until the terms say otherwise.
- Automated use: Google's general terms limit automated access; Flow's own terms not yet read.
