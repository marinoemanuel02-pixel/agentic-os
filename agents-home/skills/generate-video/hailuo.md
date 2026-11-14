# Hailuo recipe

Last verified 2026-11-14 (first frames-to-video test, English UI). hailuoai.video, signed in by the operator.

- **Quota: FLAGGED, probably not daily.** The account showed 150 credits and no daily refresh anywhere in the app;
  the plan page lists only paid monthly plans, and recent third-party reviews describe the free credits as a one-time
  trial that expires after about 3 days. Check whether the balance refilled the next day before relying on it.
  Cost seen: MiniMax H3, 2K, 5 s = 60; 768p, 5 s = 35.
- **Mode:** in the Create Video bar, the reference chip ("Omni Reference") opens a menu: **Start/End Frame**. The
  Start Frame and End Frame tiles each hold an `input[type=file]`; find each by its label and set it.
- **Prompt:** the editor is a `contenteditable` whose state ignores script inserts ("Please enter a description"):
  focus it, clear it, and type with real keystrokes (the browser tool's `type`). Resolution and duration sit in the
  "2K · 5s" chip. Press Create with a real click: a scripted click sent no request.
- **Time:** about 2-3 minutes. The page moves to `/create/image-to-video` and shows "Generating...".
- **File link:** the result's `<video>` source, `cdn.hailuoai.video/moss/prod/<date>/video/<id>_video_raw_<hash>.mp4`
  (ignore `public_assets` demo videos).
- **Output:** 1344x768 (not 16:9: scale or crop to 1280x720 before joining), 24 fps, 5.2 s, audio track, a
  "MINIMAX | Hailuo AI" watermark at bottom right (keep it).
- **Measured (page to watching-arc pair):** endpoint RMSE 4.1 % (inflated by the 1344x768 frame). Motion only from
  frame 43 to frame 80 of 124: 1.8 s still, a fast 1.5 s burst, then a hold. Usable after trimming both ends.
- **Terms:** not yet read first-hand.
