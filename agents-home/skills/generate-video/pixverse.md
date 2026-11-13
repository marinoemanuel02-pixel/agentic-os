# PixVerse recipe

Last verified 2026-11-14 (first frames-to-video test, English UI). app.pixverse.ai, signed in by the operator.

- **Quota:** daily. The page says "Come back tomorrow for your Daily 30 Free Credits" (first-hand); the account showed
  60 on the first day. Cost seen: V6, 720p, 5 s, audio on = 50; audio off = 40. Third-party guides put 360p silent
  at about 25, so the daily 30 buys about one 360p take; 720p needs two days of credits.
- **Mode:** the creation bar's **Transition** tab (first and last frame). It has two `input[type=file]` (png, jpeg,
  webp); set the first with the start keyframe and the second with the end keyframe (`DataTransfer` + `change`).
- **Prompt:** the bar's `textarea` (placeholder "...between the first and last frames"): set its value with the native
  setter and dispatch `input`. Turn the Audio toggle off (we mix our own sound). Press Create.
- **Time:** about 1 minute in the free queue.
- **File link:** open the take (`/video/<id>`), click the player once; the file shows up in
  `performance.getEntriesByType('resource')` as `media.pixverse.ai/pixverse%2Fmp4%2Fmedia%2Fweb%2Fori%2F<id>_seed<n>.mp4`
  (no signature; fetch it directly).
- **Output:** 1280x720, 24 fps, 5.04 s, no audio track when audio is off. No watermark seen on the free take.
- **Measured (page to watching-arc pair):** endpoint RMSE 0.7 % start, 1.1 % end (the best of four; Flow 1.1 / 1.7 %).
  Motion starts at frame 1 and runs to frame 119 of 121: the end frame is reached by motion, nothing held.
- **Terms:** not yet read first-hand; record `--commercial unknown` until they are.
