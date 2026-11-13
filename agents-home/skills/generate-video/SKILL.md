---
name: generate-video
description: Make a generated transition, asset or clip for a film on a free video generator (Flow, Kling) driven in the built-in browser, and take it into the film with its rights. Use for a shot marked generated in shots.md.
---

# Generate video

Generated material is opt-in per shot (rule R59): the shot list says why code or real material will not do, and a
take that reads as generic AI output is discarded. Platform recipes: `flow.md`, `kling.md` in this folder. Each holds
only what was seen on the page, dated; a step that no longer matches the page stops the run and is reported.

## The operator does

One sign-in per platform in the built-in browser (it persists), CAPTCHAs, any rights or terms dialog the platform
shows, the film's download budget (`aos asset budget --approve <MB> --by-user`), and the keep verdict on proposed takes.
Never sign in, never track or switch accounts. When a platform's credits run out, stop using it and report when the
page says they reset.

## Steps

0. **Sign-ins first.** At the start of the run, open each platform the film will use in the built-in browser and
   check that it shows the account, not a sign-in page; ask for every missing sign-in in one message before building
   anything, so the operator is not interrupted mid-run. The built-in browser's profile persists across sessions, but
   a sign-in belongs to the platform's domain: on 2026-11-13 both platforms had moved (labs.google/fx to
   flow.google.com, app.klingai.com to kling.ai) and both showed sign-in pages again.
1. **Terms first.** Before a platform's first use in a film, read its terms on automated use and on commercial use of
   free-plan output; note the URL and date. If they forbid automated access, do not drive it: write a prompt sheet
   (keyframes, prompt, seconds, aspect) for the operator instead.
2. **Keyframes from the film's code.** Render the last frame of the shot before and the first frame of the shot after
   (`tools/still.sh <frame> <CompositionId>`, film resolution), then scale to the platforms' 1280x720 (720x1280
   vertical): `magick in.png -resize 1280x720 out.png`.
3. **Generate.** Open the platform, check the credits it shows, follow its recipe. Write the prompt from the film's
   style lock: locked-off camera unless the shot needs a move, no text, same background, and ask for the motion to
   resolve into the last frame (in the 2026-11-12 spikes, one take per platform, Flow faded the target in and Kling
   started its motion abruptly).
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

Exact keyframes (metacognition-explainer, 2026-11-13): draw the boundary frames as a pure SVG string in the film's
code (one function of a state, which the shots also draw every frame), pass that markup into the page (6-10 KB per
key; send only the part that differs from a key already there), draw it on a 1280x720 canvas, `toBlob` a PNG, wrap it
in a `File` and drop it. The page draws the same markup Remotion renders, so the keyframes match the film exactly.
