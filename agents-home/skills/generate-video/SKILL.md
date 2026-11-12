---
name: generate-video
description: Make a generated transition, asset or clip for a film on a free video generator (Flow, Kling) driven in the built-in browser, and take it into the film with its rights. Use for a shot marked generated in shots.md.
---

# Generate video

Generated material is opt-in per shot (rule R55): the shot list says why code or real material will not do, and a
take that reads as generic AI output is discarded. Platform recipes: `flow.md`, `kling.md` in this folder. Each holds
only what was seen on the page, dated; a step that no longer matches the page stops the run and is reported.

## The operator does

One sign-in per platform in the built-in browser (it persists), CAPTCHAs, any rights or terms dialog the platform
shows, the film's download budget (`aos asset budget --approve <MB> --by-user`), and the keep verdict on proposed takes.
Never sign in, never track or switch accounts. When a platform's credits run out, stop using it and report when the
page says they reset.

## Steps

1. **Terms first.** Before a platform's first use in a film, read its terms on automated use and on commercial use of
   free-plan output; note the URL and date. If they forbid automated access, do not drive it: write a prompt sheet
   (keyframes, prompt, seconds, aspect) for the operator instead.
2. **Keyframes from the film's code.** Render the frame before and the frame after the generated shot as PNG stills
   (`tools/still.sh`), 1280x720 (720x1280 vertical).
3. **Generate.** Open the platform, check the credits it shows, follow its recipe. Write the prompt from the film's
   style lock: locked-off camera unless the shot needs a move, no text, same background, and ask for the motion to
   resolve into the last frame (both platforms otherwise land it abruptly or fade it in).
4. **Take it in.** Get the take's file link (recipe), then:
   `aos asset fetch --film <dir> --id <aNN> --url <file link> --kind clip --basis generated --acquisition platform-feature --platform <flow|kling> --license-url <terms page> --terms-read <YYYY-MM-DD> --watermark yes|no --commercial yes|no|unknown --prompt "<prompt>" --why "<need>"`.
   The film's `sourcing.json` must have `"generated": {"allowed": true}`; a monetized film admits only `--commercial yes`.
5. **Review.** Make review sheets; judge each take against R04 and the style lock; keep or discard with a one-line
   reason. Takes without keyframes (text-only clips and assets) get a blind review from the other vendor first.
   Never crop, cover or remove a watermark.
6. **Join.** Find where the take stops moving and trim the still tail:
   `ffmpeg -nostdin -i take.mp4 -vf "scale=320:-1,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=motion.txt" -f null -`
   (frame-to-frame difference per frame; trim where it stays near 0). Crossfade about 4 frames into the take and
   10-12 frames out of it (ffmpeg `xfade=transition=fade`, or `GlTransition` in the film), then measure the joined
   cut the same way: a value far above its neighbours at a seam is a jump frame.

## Local files into the page

The built-in browser cannot hand a local file to a page (no file picker, no fetch from a local server, no synthetic
paste). Try, with one real call each (R08): Claude in Chrome's `file_upload` tool on the platform signed in there;
else pass the PNG's bytes into the page and build a `File` there. The 2026-11-12 spikes redrew simple keyframes on a
canvas inside the page, which only matches the film exactly for simple geometry.
