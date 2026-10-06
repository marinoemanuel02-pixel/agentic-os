---
name: video-references
description: Build or refresh a reference pack for a video's niche - 3-5 strong channels, 2 recent videos each, watched in the built-in browser without downloading, notes per beat (cut rate, b-roll share, imported material, overlays, transitions, sound, how sources are credited). Use at the brief stage of any film, or when the user names a new niche or channel.
---

# Video references

A reference pack says what the best channels in a niche actually do on screen, so a film borrows practice instead of
guessing. Packs are per niche, dated, and grow across films; no niche is built in, and the brief chooses what to
borrow (rule R39 sources by need; the pack shows what "real material" means in that niche).

## Steps

1. Read `~/.agents/video/refs/<niche>.md` if it exists. Refresh it when it is older than 30 days or the brief names a
   channel it lacks.
2. Find channels: search for the niche's most-viewed explainers of this year; prefer channels with consistent craft
   over one viral video. Note each channel's URL, subscriber and view counts, and the date you read them.
3. Watch without downloading: open each video in the built-in browser, decline cookie banners, and sample frames
   from the page's `<video>` element onto a canvas every 3 s for the first 60 s and around one mid-video sequence
   (the method of `alignment-now/docs/reference-study.md`). Save the sheets in `~/.aos/refs-cache/<niche>/`, never
   in a repo. Do not use yt-dlp for references.
4. Per video, per beat, write: shots per minute; the longest hold; the share of imported real material (stock,
   archival, news, screen captures, product UI, papers) against built graphics; kinds of overlays and labels;
   transition types; sound (music bed, effects, silence); how a source is credited on screen.
5. Write `~/.agents/video/refs/<niche>.md`: a dated section per channel, then "What works" and "What not to copy"
   (their characters, palettes and signature metaphors stay theirs). The film's `refs.md` lists what this film
   borrows and why.
6. Say what frames cannot establish (voice, pacing in motion, sound) per rule R14.

## Output shape

```markdown
# <niche> reference pack (YYYY-MM-DD)

## <Channel> (<url>, <subscribers> on <date>)
| Video | Date | Length | Shots/min | Imported share | Transitions | Credits on screen |
|---|---|---|---|---|---|---|

Per beat: ...

## What works
## What not to copy
## Not established
```
