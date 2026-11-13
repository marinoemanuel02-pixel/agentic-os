# Vidu recipe

Last verified 2026-11-14 (first frames-to-video test, English UI). www.vidu.com, signed in by the operator.

- **Quota:** daily, amount unconfirmed. Vidu's own FAQ says "Daily Login: Earn credits by logging in every day" with
  no figure (a third-party guide says 5 a day, expiring the same day). The account showed a 65-credit reward badge on
  the first day. Cost seen: Vidu Q2, 1080p, 5 s = 10 credits.
- **Mode:** `/create/img2video` (Image to Video). The default model (Vidu Q4 Preview) offers only a first frame; pick
  **Vidu Q2** in the Model list to get **Frame 2** (the end frame). The frame strip's container holds one
  `input[type=file]` per slot: set the first with the start keyframe, then the second with the end keyframe
  (setting the first one twice replaces frame 1). The strip then shows "1 -> 5s -> 2".
- **Prompt:** the left panel's `textarea`: native value setter + `input`. Press "Create 10".
- **Time:** about 1-2 minutes.
- **File link:** the result's `<video>` source, `vidu.cf.vidu.studio/infer/tasks/.../creation-02/watermarked.mp4?...`
  (signed, expires in days). Fetch it with `--watermark yes`.
- **Output:** 1920x1080, 24 fps, 5.1 s, a "Vidu AI" watermark at bottom right (keep it).
- **Measured (page to watching-arc pair):** endpoint RMSE 2.3 % start, 2.5 % end. Motion from frame 23; the arc is
  complete by about mid-take and the second half barely moves: trim the still tail (SKILL.md step 6).
- **Terms:** not yet read first-hand; free output is reported non-commercial: record `--commercial no` until read.
