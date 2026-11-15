# Google Flow recipe

Last verified 2026-11-13 (metacognition-explainer, account UI in Italian; labels follow the account language).
Flow now lives at flow.google.com (it was labs.google/fx on 2026-11-12).

## Observed

- **Start:** the Flow home page, Nuovo progetto. A project opens with an assistant panel ("Agente") on the right and
  the media grid on the left. Emulate a 1440x900 viewport: in the narrow pane the settings menus open off-screen.
- **Direct mode:** the prompt bar's "Agente" chip toggles the assistant; with it off (aria-pressed false) the bar
  shows a settings chip (aria-label "Trigger impostazioni"). In it: Video (not Immagine), then **Fotogrammi**
  (frames), 16:9, the model (Veo 3.1 - Lite was the default) and the take count. It shows the cost: x2 = 20 credits.
- **Upload:** a drop event (dragenter, dragover, drop with a DataTransfer of Files) on `.grid-area-wrapper`, the
  "Inizia a creare o trascina contenuti multimediali" area. No image-rights dialog appeared on 2026-11-13 (it did on
  2026-11-12).
- **Slots:** the bar shows `button.empty-chip` "Inizio" and "Fine". Clicking one opens "Seleziona un'immagine del
  frame": pick the image, then "Aggiungi al prompt". After a generation the slot did not reopen the picker on a
  click; reloading the project page and calling `.click()` on the `button.empty-chip` from a script did.
- **Generate:** click the prompt box, type, press the arrow. Two takes took about 1.5-2 minutes.
- **File link:** open the take (`/project/<id>/edit/<id>`). Since 2026-11-14 the take page is a scene editor with no
  `<video>` and no video in the resource list until a download starts. What worked (2026-11-14/15): wrap
  `window.fetch` to log URLs containing `flow-content.google/video`, override `HTMLAnchorElement.prototype.click` so
  the page's save does nothing, press "Scarica contenuti multimediali" > "720p"; the signed link appears in the log.
  Fetch it soon (expiry about 6 hours). Each take of a pair has its own edit page.
- **Mode (2026-11-15):** the bar may open in image mode (Nano Banana); its settings panel switches to Video >
  Fotogrammi (frames), Veo 3.1 - Lite, x1/x2. The frame picker's "Carica contenuti multimediali" button calls
  `input.click()`, so a patched click feeds the keyframe `File` (SKILL.md, local files).
- **Output:** 1280x720, 24 fps, 7.93 s, with an audio track.
- **Behaviour:** both keyframes matched in geometry (RMSE 1.1-1.7 % against the keyframe), the background slightly
  darker. On 2026-11-13 the motion ran to the last frame (no still tail) and reached the end frame by motion. Of
  2 + 2 takes, two were discarded: a mist that read as a mushroom cloud with stray side arcs, and a dial needle that
  swept four times and vanished in between (an AI artifact in the centre of the frame).
- **Credits:** two x2 generations (40 credits) left too few for a third; the page then showed "Non disponi di crediti
  sufficienti" with an upgrade button (never click it). A later x1 request (10 credits) was accepted by the bar but
  refused on submit with the banner "Hai esaurito i crediti Google Flow" and no take: read the banner, not the bar.
  Check which account the avatar holds (its aria-label names it) before assuming fresh credits.
- **Watermark:** none visible.

## Terms

- Google Terms of Service (policies.google.com/terms, read 2026-11-13): automated access is barred only "in violation
  of the machine-readable instructions on our web pages" (robots.txt); flow.google.com serves no robots.txt (the path
  returns the app page) and labs.google's robots.txt disallows only /404. Google does not claim ownership of
  generated content; no statement found on commercial use of free-credit output: record `--commercial unknown`.
