---
name: generate-video
description: Make a generated clip, transition or asset on a free video generator without a watermark (Flow, PixVerse) driven in the built-in browser, finish it to blend with the film's code shots, and take it in with its rights. Use only for a shot marked generated in shots.md, i.e. material the film's code cannot make.
---

# Generate video

Code first. A film's own code (Remotion, three.js, its rigged cast) draws its world exactly, at full quality, with
joins that match to the pixel and changes that cost one re-render. A video generator is an additional resource for
what that code cannot make, used per shot (rule R59): the shot list says why code or real material will not do, and a
take that reads as generic AI output is discarded. Platform recipes in this folder: `flow.md`, `pixverse.md`. Each
holds only what was seen on the page, dated; a step that no longer matches the page stops the run and is reported.

## When a generated clip earns its place

Use one for material outside the film's code world, where building it would cost far more than the take:

- photoreal footage the film has no source for (places, people, objects in the real world);
- natural phenomena and soft matter at a detail code cannot reach cheaply: fire, smoke, water, cloth, hair in wind,
  crowds, weather;
- a painterly or stylised sequence in a look the film's renderer does not have (an inserted memory, a dream);
- an organic transformation of something that only exists as footage.

Do not use one for anything already in the film's 3D or vector world: camera moves, transitions between two code
scenes, a rigged character's acting, particles, light, morphs between two scenes the code draws. The code does these
better. metacognition-3d (2026-11-14/15, v6-v10) is the worked case: five generated transitions between code shots
cost credits, sign-ins after every browser reset, keyframe transfers, a visible softness at each one, watermarks, and a
remake of every take whenever a pose was fixed; v10 replaced all five with code (lines lifting off the page, her mesh
breaking into points that become the mind and back, a camera rise) and every join matched to about 1 %.

## Blending a take into the code shots

- Keyframes come from the film's code (step 2), so the take starts and ends on the exact neighbouring frames.
- One finish over every shot: the film's grade, grain and overlay go on the take too (`grade={false}` only keeps the
  take's own colours when the grade would open a seam; the 2D overlay still applies).
- Upscale soft output before it goes in: generators give 720p or less, the film is 1080p. An anime/cel model
  (Real-ESRGAN anime video) for toon films, a general model otherwise; the download needs the operator's OK with its
  size (memory: installs need consent).
- Keep takes short, never two generated shots back to back, and cut on motion rather than fading (no fades unless
  the film's style asks for them).

## Providers (frames-to-video tests 2026-11-14/15; `measure-takes.sh` compares takes)

| Provider | Free quota | Cost per 5 s take | Endpoint RMSE start/end | Motion | Watermark |
|---|---|---|---|---|---|
| Flow (Veo 3.1 Lite) | daily 50 per Google account | 10 (720p, x1); x2 = 20 | 1.1 / 1.7 % | to the end frame | none |
| PixVerse (V6, Transition) | daily 30 | 30 (540p silent), 40 (720p silent) | 0.7 / 1.1 % | to the end frame | none seen |

Watermarked providers are not used (operator's decision 2026-11-15): Kling ("KlingAI"), Vidu ("Vidu AI") and Hailuo
("MINIMAX / Hailuo AI") put a logo on free output, and Vidu's terms forbid removing, altering or obscuring it, so a
take from them cannot blend in. Their recipes were removed; git history keeps them (`kling.md`, `vidu.md`,
`hailuo.md` before 2026-11-15).

## The operator does

One sign-in per platform in the built-in browser, CAPTCHAs, any rights or terms dialog the platform shows, the film's
download budget (`aos asset budget --approve <MB> --by-user`), and the keep verdict on proposed takes. Never sign in,
never track or switch accounts yourself. When a platform's credits run out, stop using it and report when the page
says they reset. Sign-ins do not survive a closed Browser pane or an app restart (seen 2026-11-14 and 2026-11-15).

## Steps

0. **Sign-ins first.** At the start of the run, open each platform the film will use in the built-in browser and
   check that it shows the account, not a sign-in page; ask for every missing sign-in in one message before building
   anything, so the operator is not interrupted mid-run.
1. **Terms first.** Before a platform's first use in a film, read its terms on automated use and on commercial use of
   free-plan output; note the URL and date. If they forbid automated access, do not drive it: write a prompt sheet
   (keyframes, prompt, seconds, aspect) for the operator instead.
2. **Keyframes from the film's code.** Render the last frame of the shot before and the first frame of the shot after
   (`tools/still.sh <frame> <CompositionId>`, film resolution), then scale to the platforms' 1280x720 (720x1280
   vertical): `magick in.png -resize 1280x720 out.png`.
3. **Generate.** Open the platform, check the credits it shows, follow its recipe. Write the prompt from the film's
   style lock: locked-off camera unless the shot needs a move, no text, same background, and ask for the motion to
   resolve into the last frame.
4. **Take it in.** Get the take's file link (recipe), then:
   `aos asset fetch --film <dir> --id <aNN> --url <file link> --kind clip --basis generated --acquisition platform-feature --platform <flow|pixverse> --license-url <terms page> --terms-read <YYYY-MM-DD> --watermark no --commercial yes|no|unknown --prompt "<prompt>" --why "<need>"`.
   The film's `sourcing.json` must have `"generated": {"allowed": true}`; a monetized film admits only `--commercial yes`
   (PixVerse free output is non-commercial: terms read 2026-11-14).
5. **Review.** Make review sheets; judge each take against R04 and the style lock; keep or discard with a one-line
   reason. Takes without keyframes (text-only clips and assets) get a blind review from the other vendor first.
6. **Join.** Find the frame that best matches the next shot's first frame (`measure-takes.sh`, then a per-frame RMSE
   search over the last 30 frames) and trim there; trim a still tail where the frame-to-frame difference stays near 0:
   `ffmpeg -nostdin -i take.mp4 -vf "scale=320:-1,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=motion.txt" -f null -`.
   Measure the joined cut the same way: a value far above its neighbours at a seam is a jump frame.

## Local files into the page

The built-in browser cannot hand a local file to a page (no file picker, no fetch from a local server, no synthetic
paste). Try, with one real call each (R08): Claude in Chrome's `file_upload` tool on the platform signed in there;
else pass the image's bytes into the page and build a `File` there.

Exact keyframes (metacognition-explainer, 2026-11-13): draw the boundary frames as a pure SVG string in the film's
code (one function of a state, which the shots also draw every frame), pass that markup into the page (6-10 KB per
key; send only the part that differs from a key already there), draw it on a 1280x720 canvas, `toBlob` a PNG, wrap it
in a `File` and drop it. The page draws the same markup Remotion renders, so the keyframes match the film exactly.

Raster keyframes (3D renders, metacognition-3d, 2026-11-13/15): a real Ctrl+V into the page fires no paste event, the
page may not read the clipboard, and an https page cannot fetch a localhost server even with CORS and
Private-Network-Access headers. What worked: WebP at 854x480 q40 (20-27 KB), base64, split into 3000-character
chunks, each sent with a page-side 32-bit hash (x = (x*33) ^ c, seed 5381) that is compared with the local one; the
page joins them, decodes the WebP with `createImageBitmap`, draws it on a 1280x720 canvas and builds the PNG `File`.
Where a page opens its picker from a menu item (Flow's "Carica", PixVerse slots), patch
`HTMLInputElement.prototype.click` to feed the pending `File` to the input instead of opening the dialog.
