<!-- Provenance: ChatGPT Deep Research report, pasted by the operator on 2026-10-26 in answer to the
"ChatGPT Deep Research" prompt written for the cast v2 work (practices, pipelines, two-week plan). Kept as research
input, not as a decision: the operator said both reports are bases, not absolutes. Diagnosis and practice sections as
pasted; the pipeline, two-week and agent sections lightly condensed; the report's inline citation markers were not
carried over (it named its sources in prose). The report could not see the attached images, so its diagnosis is
inferred from the described construction. -->



From "Programmer Art" to Production Character Design: A Two-Week Remotion Plan

## Executive judgment

The core problem is probably not React, Remotion, SVG, or insufficient rendering effects. It is that your current
abstraction appears to start too far downstream: you are parameterizing anatomical construction and rendering
treatment before a human designer has locked appealing shapes, character-specific proportions, silhouette, posing
language, and acting. Professional character-design practice generally works in the opposite order. Stephen Silver
explicitly puts story → gesture → design → form → details, with cleanup, color, and texture last; Disney describes
visual development in terms of appeal, color, design, and composition, not technical complexity.

That distinction matters because your current list—5.5-head proportions, tapered limb outlines, hand silhouettes, shoe
soles, bean eyes, visemes, cel shadows, rim lights, colored outlines, grain—contains a lot of implementation
sophistication, but relatively little evidence of designed specificity. A generic body made technically more
sophisticated still reads as a generic body. Preston Blair makes essentially this point from an animation perspective:
merely having body, head, facial features, and hands is not enough; they have to remain proportionally coherent while
reading as a believable living character, and character development also requires individual shape, personality,
features, and mannerisms.

My blunt recommendation: stop developing the final lead-character contours procedurally. Keep your procedural system
as the rig underneath, but replace its visible "skin" with a small set of human-designed master SVGs and
human-designed replacement shapes. The best architecture for your constraints is:

artist-designed SVG skin + procedural skeleton + curated replacement drawings + Remotion-controlled animation

Do not abandon Remotion. Remotion works directly with React/SVG and frame-derived animation, and its current Studio
tooling can expose SVG/HTML elements for visual editing. The rendering stack is not what is making the characters look
cheap.

Do not switch the project to Rive, Spine, Lottie, or Grease Pencil during this two-week rescue unless you discover a
specific blocker in SVG. Rive and Spine can produce excellent character rigs, but they conflict with your strict
free-tool requirement in practical production use: current Rive free exports include a Rive splash screen, while
removing it requires a paid tier; Spine's production editor/export workflow is commercial.

The strongest evidence for the hybrid recommendation is actually your target. Kurzgesagt describes its own process as
sketching visual ideas first, then producing vector/pixel illustration, followed by "meticulous handiwork" in
animation; its published training workflow likewise starts from authored illustration assets rather than generating
final character design from anatomical parameters. "Kurzgesagt-like" therefore should mean disciplined shape design
and art direction, not "generic SVG person + more cel shading."

Attachment limitation: the cast sheet and latest-film frame were not retrievable in the research environment available
to me. I therefore will not pretend to have visually inspected them. The diagnosis below is based on the exact
construction system you described and is written as a set of concrete tests to run against those two images. Where I
say "likely," it is an inference rather than an observation of the missing attachments.

## Why the current characters probably read as "programmer art"

"Programmer art" in this context does not mean "made in code." Code can reproduce extraordinary design. It means the
picture appears to have been derived from rules rather than authored around visual decisions. The tell is usually that
every local problem has a technically reasonable solution, while the whole character lacks a strong idea.

### The primary shapes are probably too generic

A fixed or near-fixed 5.5-head mannequin is a sensible construction scaffold, but it is a weak character-design system
if most of the cast inherits the same torso/limb topology. A professional lineup usually gets much of its appeal from
differences in the large masses: head-to-body relationship, shoulder width, rib cage versus pelvis, length
distribution, stance, taper, hair mass, clothing silhouette, and the relationship between small, medium, and large
shapes.

Silver's design framework explicitly includes shape, proportion, balance, variety, and harmony, and his warning is
useful here: finishing details cannot compensate for an unresolved underlying design. Blair similarly says each
character needs its own shape, personality, features, and mannerisms.

A useful failure test is brutally simple: fill every character completely black, remove hair color, skin color, facial
features, internal lines, shadows, rims, and grain, then put the cast side by side. If the director cannot immediately
tell which silhouette is which, you do not yet have a cast. You have one procedural body generator with costumes.

For a lead cast, I would deliberately create at least three different body grammars, not merely three parameter
presets:

| Archetype | Deliberately different design grammar |
|---|---|
| Compact | large head, compressed torso, short forearms/calves, broad hand shapes, low center of mass |
| Long | smaller head, narrow rib cage, long forearms/shins, sharper clothing shapes, high center of mass |
| Broad | smaller head-to-shoulder ratio, strong torso wedge, thick upper limbs tapering decisively, comparatively small extremities |

Those should be drawn until appealing first. Only afterward should numbers be extracted from them.

### The limb system is probably mathematically smooth rather than graphically designed

"Tapered limb outlines through shoulder/elbow/wrist" is exactly the kind of construction that works in a rigging
diagram but can betray itself in final art. A generated arm tends to become a tube with a bend in it: the inside and
outside contours respond too similarly, elbows become mechanical hinge points, and every pose preserves the same
mathematical taper.

Professional-looking flat characters frequently cheat this. The contour on the compression side of an elbow may pinch;
the opposite side may become one long clean curve. A forearm in a presenting gesture may be broader than anatomy would
dictate because the silhouette needs it. A shoulder may disappear into the torso in one view and be redrawn as a cap
shape in another.

That principle follows the larger animation distinction between construction and the final drawing. Disney describes
character form in terms of weight and presence, while Animation Mentor's current posing lesson explicitly recommends
treating poses "like drawings" and notes that extra curvature controls can make a limb feel more drawn—but also
emphasizes that such polish cannot rescue a bad pose.

So: do not require one arm path to survive every angle. Have interchangeable upper-arm/forearm drawings for: neutral
side view, foreshortened 3/4, elbow compression, arm toward camera, hand-on-hip/contact poses. That sounds less elegant
architecturally. It will look much better.

### Uniform line treatment is likely making the drawings look diagrammatic

A program naturally wants one outline-width parameter. An illustrator does not. Even in a deliberately clean flat
style, line quality benefits from hierarchy: silhouette versus internal detail, foreground versus background edge,
contact/compression areas, and sometimes shadow-side versus light-side contour. Line-art guidance from Clip Studio
similarly recommends varying contour emphasis and using line weight to support depth rather than applying one
indiscriminate width.

For your style, I would not add "sketchiness." I would instead enforce a restrained hierarchy:
- outer silhouette: approximately 1.4–1.7× your facial/internal line
- major overlap/contact line: approximately 1.1–1.3× internal line
- face: thinnest and simplest
- hair/clothing outer edge: allowed to merge into the silhouette rather than outlining every sub-shape

Those ratios are proposed production specs, not canonical industry rules. Their purpose is to stop everything from
having equal visual importance.

Also inspect every frame for tangencies: wrist exactly kissing torso edge, shoe edge tangent to trouser edge, hand
tangent to face, forearm line coinciding with torso contour. Procedural geometry produces these accidentally; good
posing actively separates or deliberately overlaps them.

### Your hand library may be correct as icons and wrong as acting

A hand silhouette library is a good engineering primitive. The danger is making hands into symbols that get attached
to wrists: openHand, pointHand, fist, gripHand. Blair treats hands as one of the fundamental constructed parts of the
character, not decorative appendages. Animation Mentor's pose critique similarly calls out readable hand shapes as
part of a strong pose and warns against hiding the acting inside the body's silhouette.

Each production hand needs four things your API should represent: palm direction + wrist attitude + finger grouping +
acting intention. "Presenting something" is not simply an open palm. A hesitant presentation, sales-pitch
presentation, accusation, reassurance, and "look over there" all have different wrist/finger energy.

For flat animation, you do not need anatomically elaborate fingers. You need clean groupings. Treat four fingers as one
dominant graphic mass plus one or two strategically separated digits. Spend disproportionate effort on the
wrist-to-palm transition: this is where many modular rigs look assembled.

Make a curated hand sheet of roughly 12–16 production poses, with left/right variants checked rather than blindly
mirrored: relaxed, half-open, broad presentation, soft presentation, index point, whole-hand point, pinch, cylinder
grip, phone/card grip, flat palm, fist, thinking/chin contact, crossed-arm contact, pocket entry, typing/tapping, and
one character-specific gestural hand.

### The feet may contain detail without containing weight

"A shoe with a sole" sounds more finished than a primitive oval, but a sole does not solve the major problem: does the
body actually appear to stand on it? Good posing requires believable weight and balance. Animation Mentor's
solid-drawing material emphasizes gravity and support; its 2026 posing tutorial goes all the way down to foot
placement and planted contact because foot mechanics affect whether the body feels grounded.

Your shoe needs to be designed first as a foot wedge, then as footwear. At minimum, design separate drawings for:
planted 3/4, planted profile, heel raised, toe raised, front-ish view. Do not rotate one profile shoe through every
pose. A common synthetic-looking failure is that both shoes have identical angle and contact while the hips claim the
weight is on one leg. That contradiction instantly makes a character feel like a puppet.

### Bean eyes plus viseme mouths can become an "emoji face"

Bean eyes are not inherently low quality. Very simple faces can be excellent. The failure happens when the face is
assembled as independently controlled symbols: eye + eye + lid + mouth-shape. Then an angry line is simply an angry
mouth underneath the same head; a worried viseme is the same viseme with different eyebrows; the cheeks, jaw, head
angle, eye aperture, and mouth corners do not participate in the thought.

Toniko Pantoja's character-design teaching emphasizes making expressions, emotions, and poses believable and readable,
not merely maintaining a recognizable symbol set. Animation acting material makes the same point at the body level:
pose and expression need one coherent intent.

For your rig, expression should sit above viseme, not beside it:
finalFace = characterIdentity + emotionalExpression + speechViseme + blink/gaze

The emotion layer should be allowed to modify the speech layer. "AH" while terrified should not have the same contour
as "AH" while calmly explaining. At small sizes, I would prioritize: eye aperture, eyebrow angle/height, mouth corner
attitude, head tilt, jaw/opening, only then minor mouth detail. Do not add a nose merely to look more "designed." Add it
only if it contributes a distinctive facial mass or is required for 3/4 orientation.

### Cel shadow, rim light, and grain may be making the problem worse

This is probably the most important diagnosis after silhouette. Silver's hierarchy puts details—including color and
texture—after story, gesture, design, and form, and specifically warns that rushing to details produces
finished-looking work that still lacks the earlier fundamentals. That sounds extremely close to your situation.

A fixed cel shadow and rim treatment can advertise the procedural system rather than conceal it. In a night scene, ask:
Where is the actual key light? Why is the rim on that side? Does the face receive the same environmental logic as the
torso? Does the character cast or receive light like surrounding objects? Is the rim separating an important edge, or
outlining the whole body like a sticker? If every person gets a pleasing cyan rim regardless of scene geometry, the
characters will feel composited onto the environment rather than resident in it.

Similarly, paper grain should be part of a scene-level material language, not a filter applied independently to each
body part. Pixar's recent stylized rendering work provides a useful analogue: in its "Cardboard" look-development
example, noise is used to break harsh synthetic toon boundaries and a real paper texture is overlaid to establish an
integrated illustrative surface. The useful lesson is not "add more noise"; it is that texture has to be art-directed
and coherent.

### Posing is likely the biggest motion-quality gap

A rig can satisfy every joint constraint and still have no pose. The current Animation Mentor pose framework is
unusually relevant to your case: judge a pose by meaning, silhouette, line of action, and contrapposto. It specifically
identifies symmetry, screen-parallel body lines, hidden hand acting, and unclear negative spaces as reasons poses feel
lifeless. Another Animation Mentor resource defines line of action as a force that runs through and unifies the whole
body, and warns that mirrored limbs make poses flat.

That should become part of your pose API philosophy. Your neutral standing pose should not be: torso 0°, hips 0°,
shoulders 0°, head 0°, feet symmetric, both elbows slightly bent. Even your "neutral" needs a decision: which leg owns
the weight, which shoulder drops, where the head counter-tilts, where the empty hand rests, and what attitude the spine
carries.

The final performance test is: freeze the shot before adding speech animation. Does the still frame already tell me
what the person is thinking? If not, better visemes will not help.

## What makes simple 2D humans look professional

The professionals and teachers you named converge on a surprisingly consistent hierarchy. Simple is not the enemy.
Undesigned is. Disney's own visual-development description says designers establish the look of characters and worlds
through appeal, color, design, and composition. Preston Blair moves from construction into individual
shape/personality/mannerism. Walt Stanchfield's Drawn to Life lectures are centered on gesture rather than literal
copying of surface anatomy. Silver's five-part hierarchy is story, gesture, design, form, details. Contemporary
animation training still assesses poses through meaning, silhouette, line of action, weight, and contrast.

That gives you a useful production order:
idea → gesture → silhouette → shape relationships → construction → face/hands → color/value → line polish → lighting → texture

Your current system sounds closer to:
construction → components → line → face symbols → shader effects → texture → pose

Reverse that.

### Shape language and appeal

Do not interpret "appeal" as "cute." In animation, appeal is closer to clarity, specificity, charisma, and pleasing
organization. Disney explicitly lists appeal as a visual-development skill, and the traditional principle is
associated with making a character compelling to look at rather than merely attractive.

For each cast member, write a one-sentence visual thesis before drawing: "Competent but chronically tired researcher:
upright narrow torso fighting against a forward head, oversized soft cardigan mass, precise small hand gestures." That
sentence should alter the silhouette.

A useful Silver-style shape pass is to ask whether the design has variety rather than evenness. Avoid: equal
head/torso/leg visual masses, three equal-width limb segments, equal gaps between all features, identical eye sizes
unless stylistically deliberate, perfectly centered costume details, equal curves on both sides of every body part.
A professional flat character often feels simpler than amateur work precisely because an illustrator has made
stronger choices about what to combine.

### Construction should survive simplification

Blair is useful here because his work does not oppose simplification and construction; it treats construction as what
allows simple shapes to remain consistent and alive. Your SVG should therefore retain an invisible construction model:
rib-cage mass, pelvis mass, shoulder line, hip line, head centerline, eye line, elbow/knee landmarks, hand palm plane,
foot wedge. But the visible path is not required to follow those construction primitives literally. This is the shift
from "drawing the rig" to "using a rig to support a drawing."

### A model sheet is more important than another renderer iteration

The design must be frozen sufficiently that your code has something authoritative to preserve. For every lead, make
one production model sheet containing:

| Sheet area | Required content |
|---|---|
| Lineup | whole cast at common scale, normal pose and black silhouette |
| Turnaround | front, 3/4, profile, back |
| Construction | head units, shoulder/hip landmarks, elbow/knee/wrist/ankle positions |
| Head | front, 3/4, profile, slight up/down |
| Expression | neutral, warm, skeptical, worried, angry, surprised, thinking, amused |
| Mouth | production visemes shown inside at least two expressions |
| Hands | 12–16 designed poses plus grip diagrams |
| Feet | five useful shoe/foot states |
| Acting | 8–12 full-body story poses |
| Props | wrist/hand anchors and standardized grip geometry |
| Palette | base, shadow, light, outline, highlight, night-scene variants |
| No-no sheet | off-model proportions, forbidden tangencies, bad hand joins, overdone rim, etc. |

Blair's emphasis on consistent proportions and believable character construction is precisely why this document
matters. Disney's modeling process likewise evaluates characters across angles and emphasizes form, weight, presence,
costume, accessories, and props as parts of the same character idea.

A no-no sheet is especially valuable for AI-assisted production. Agents are very good at converging toward
mathematically valid but aesthetically generic solutions. Give them visual constraints for what they must never
normalize.

### Line, hands, feet, and face should be designed at delivery size

Do not assess the master vectors only zoomed in. Build a permanent Remotion "model-sheet test composition" showing
each character at: hero close-up, normal conversational size, smallest full-body production size, 50% preview,
grayscale, black silhouette. A face that looks delightful at 900-pixel head height can turn into accidental
punctuation at normal explainer scale.

At the smallest expected production size, eyebrows and eyelids must not collapse into noise. Hand silhouettes should
still show the gesture. Shoe/ground contact should remain legible. These are production acceptance tests rather than
universal artistic laws.

### Color should be scripted, not attached to characters independently

Pixar's educational material describes color scripts as a way to map and unify a film's light/color vision across the
emotional progression, and its visual-language material emphasizes shape, size, color, and framing as storytelling
tools. For your night palette, define the scene first: background family → ambient fill → key light → character local
colors → accent hierarchy; not: character palette → darkened version → cyan rim.

Every important scene should have a tiny color key: a thumbnail containing the final background and at least one lead
character. Judge the pair together. In grayscale, require: head/face separable from hair where expression requires it;
hand separable from torso when gesturing; character silhouette readable against at least ~90% of its important
perimeter; one clear local contrast focal point, usually face or hands; secondary costume features visibly
subordinate. Those percentages are proposed QA thresholds, not claims about an industry standard.

### Texture should unify the frame rather than decorate the person

Kurzgesagt describes its style as authored illustration followed by meticulous animation, with both flat 2D and other
elements used as needed. That is the useful part to imitate: controlled visual hierarchy. Use perhaps three texture
layers: paper substrate (frame/world anchored); large-area tonal variation (extremely subtle); select accent texture
(only where art direction calls for it). Avoid independent random noise on every limb path. Even seeded noise can make
the body feel assembled because every component announces its own surface.

### Pose and acting should precede lip-sync

Stanchfield's gesture-centered teaching and Blair's explicit inclusion of "Animated Acting" are important antidotes to
a rig-first workflow. Animation Mentor's recent posing guidance asks whether the pose itself communicates a specific
emotional idea, and recommends acting out/reference before polishing. For every dialogue beat, build: thought → key
pose → eye direction → head attitude → hand/prop action → mouth; not: audio → visemes → arm animation. A useful acting
rule for explainer videos is one main idea per pose. When the speaker changes thought, change the body's graphic
statement. Do not continuously wiggle arms just because dialogue continues.

### The study stack I would actually use

Do not spend the fortnight trying to consume entire courses. Use these surgically:
- Preston Blair, Cartoon Animation — construction, character design/development, line of action, animated acting.
- Walt Stanchfield, Drawn to Life — gesture as communication rather than anatomical copying.
- Stephen Silver — the five-stage "Story, Gesture, Design, Form, Details" ordering as review gate.
- Toniko Pantoja — reference gathering, contrast, clear/appealing characters, expressions, and poses.
- Marc Davis / Disney Nine Old Men material — how character conception differentiates a cast.
- Animation Mentor's pose tutorials — meaning, silhouette, line of action, contrapposto, negative space, hand
  readability, weight and foot contact.
- Pixar's color-script / visual-language material — judge character and environment together.
- Kurzgesagt's own process/course material — for workflow, not for tracing their designs.

## Pipeline comparison

| Pipeline | Achievable quality for lead humans | Two-week effort | What coding agents are good for | Remotion fit | Verdict |
|---|---|---|---|---|---|
| Fully procedural SVG | Medium for graphic extras; potentially high only with enormous art-direction code | High and deceptive | geometry utilities, interpolation, variants, validation | Excellent | Keep as rig/crowd system; stop using it to invent final lead contours |
| Hand-authored layered SVG + code rig | High | Medium | import, anchors, metadata, pose system, previews, tests | Excellent | Best choice |
| Rive / Spine | High to very high | Medium–high migration cost | state machines, runtime wiring, rig tooling | Fair–good but less native than SVG | Excellent tools, wrong constraint/timing |
| Lottie with dynamic properties | High for authored motions; medium for arbitrary acting | Medium | JSON inspection, slots/tokens, playback integration | Good; official Remotion support | Useful secondary format, not ideal main acting rig |
| Blender Grease Pencil | Very high artisanal ceiling | High | automation/export, shot tooling | Weak for direct parametric control | Strong artistic tool; wrong main pipeline for this sprint |
| Licensed/open vector packs | Medium; often polished but generic | Low | layer normalization, color mapping, rig conversion | Good | Useful reference/extras; risky as hero cast |

**Fully procedural SVG.** The major advantage is obvious: your whole body is data. Poses, outfit parameters, visemes,
prop anchors, color variants, crowd generation, and deterministic rendering are easy. Procedural SVG can certainly
look polished; DiceBear is a real example of a large, deterministic, configurable SVG avatar ecosystem. But avatars and
identity graphics are exactly where standardized parametric topology is strongest. An acting human lead who needs
weight, hand performance, contact poses, foreshortening, and emotionally specific silhouettes is a much harder target.
Continuing to add procedural shape parameters to the current lead-character generator is a dead end for a two-week
rescue. Retain it for skeleton/anchors, pose interpolation, mouth timing, crowds/background people, costume color
variants, rough previz, accessibility/debug views. Stop asking it to be the character designer.

**Hand-authored vector parts, then rigged in code.** This is the sweet spot. Inkscape is the safest default (open
source, SVG-native); Penpot is also open-source and SVG-oriented; Affinity is now free (not open source); Figma Starter
is free. Substitution: Illustrator → Inkscape/Affinity; After Effects character assembly → React/SVG rig; animation
timeline → Remotion. Quality ceiling high, migration risk low, Remotion compatibility excellent. Recommended route.

**Rive and Spine.** Both solve many problems (deformable vector graphics, hierarchy, rigging, animation reuse, states,
runtime control). Rive's runtimes are open-source with no runtime royalty, but as of October 2026 the free plan's
exported .riv plays a Rive splash screen; a paid plan removes it. Spine has a proven high ceiling (e.g. Cult of the
Lamb) but its authoring/export tooling is commercial. Migrating during a two-week visual-quality emergency is the wrong
optimization.

**Lottie.** Easiest alternative to connect technically (@remotion/lottie); slots/tokens allow runtime replacement of
colors, transforms, text. Strongest when a designer has already authored the motion and code needs to place, recolor,
retime. Less elegant as the central representation for arbitrary poses, grips and dialogue. Use later for authored
loops or inserts.

**Blender Grease Pencil.** Highest artistic ceiling for hand-drawn motion (e.g. HERO); current Blender supports SVG
interoperability. Mismatch: it turns the art problem into a shot-production problem and reduces the leverage of the
React rig. Use only for hero inserts later.

**Open/licensed vector-character packs.** Humaaans (CC0), Open Peeps (CC0), unDraw (permissive license), Storyset
(attribution unless paid). Useful for studying torso/limb simplification, modular hand/arm joins, background extras,
prototype casts, how authored irregularity breaks a purely geometric look. Not for the hero cast unless heavily
transformed: "professionally drawn but obviously stock" is a different failure mode rather than a solution.

## The production architecture I recommend

Rule: let humans author taste. Let code preserve, manipulate, validate, and reuse it. Four layers:

```text
/art
  researcher/
    body-front.svg  body-3q.svg  head-front.svg  head-3q.svg  hands.svg  shoes.svg  corrections.svg
/rig
  researcher.rig.json
/poses
  researcher/  neutral.json  explain.json  skeptical.json  reassure.json  hold-phone.json ...
/animation
  Character.tsx  poseInterpolation.ts  face.ts  lipSync.ts  lighting.ts
```

The master SVG contains stable named groups, not one flattened path: back-leg-l, back-leg-r, back-arm-l, back-arm-r,
pelvis, torso, neck, head (hair-back, face: eye-l, eye-r, lids, brows, mouth; hair-front), front-arm-l, front-arm-r,
hand-l, hand-r, shoe-l, shoe-r, shadow-corrections, highlight-corrections. The rig JSON owns pivots, transform limits,
z-order options, attachment points and prop grips. The SVG owns how the character looks.

Use replacement drawings rather than demanding perfect deformation: forearm.normal / .compressed / .foreshortened;
hand.present.soft / .present.emphatic / .grip.phone; shoe.planted.3q / .heelUp; torso.front / .3q; head.front / .3q.

Separate pose from expression and speech: character = { bodyPose, gaze, expression, viseme, handL, handR, propL,
propR, lighting }, with hierarchy: expression constrains eye/lid/brow/mouth; viseme deforms the expression's mouth;
gaze may affect lids/head; bodyPose controls shoulder/hip/head counterpose; prop requests a compatible grip.

Reduce the lighting system before expanding it: during design review render with flat fills + one outline treatment +
at most one shadow family; reintroduce rim and texture only after the model sheet passes. Make lighting scene-driven
(scene.light.direction, keyColor, ambientColor, rimStrength), not a permanent character style.

Build a permanent contact-sheet renderer: cast lineup, silhouettes, front/3/4/profile, every expression, every hand,
every shoe, 12 standard poses, grayscale, night background, light background, smallest delivery size. Every asset
change regenerates this sheet.

## Two-week rescue plan and quality gate

One gold-standard character first.
- Days 1–2: freeze the visual target. 24–30 references in three categories (8–10 finished target shots, 8–10
  construction references such as model sheets/hand sheets, 8–10 acting references); a one-page style charter
  (heads, limbs, hands, feet, face, outline, light, texture, pose). Delete references that only contribute "cool
  rendering".
- Days 3–4: design one gold-standard character: 20 fast silhouette variants, best three in the rejected-shot
  background, choose one; then front, 3/4, profile, back, 8 expressions, 12–16 hands, 5 shoes, 8–12 acting poses. No
  new rig code meanwhile.
- Day 5: clean and layer the vector master in Inkscape/Affinity/Penpot with explicit pivot markers; no destructive
  optimizer. If the static assembled SVG is not good enough for the director deck, stop: do not rig bad art.
- Days 6–7: rig the approved art (importer, pivots, z-order switching, limb hierarchies, 3/4 swap, hand replacement,
  prop contract, head-space face coordinates, pose serialization, preview UI). The agent must not redraw approved
  contours.
- End of week 1: pose library of about 12 hand-authored poses (neutral attentive, neutral relaxed, explain-left,
  explain-right, emphasize, skeptical, concerned, reassure, think, listen, object, hold-primary-prop), each with a
  black-silhouette thumbnail; a pose enters the library only if it passes meaning, silhouette, line of action and
  counterpose.
- Week 2 start: rebuild facial performance; three test lines (calm, emphatic, worried) with identical phonemes must
  look different.
- Week 2 look-dev: three test backgrounds (dark quiet, dark busy, mid-value lit); per background render flat, +shadow,
  +motivated rim, +grain; the progression must add information.
- Derive the cast only after the gold character passes: change at least four primary silhouette variables per
  character (head mass, shoulder-to-hip, torso, limb rhythm, hand size, stance, hair mass, costume silhouette).
  Background characters can stay procedural.
- Final two days: rebuild one rejected shot as A (previous), B (new flat, no rim/grain), C (final lit). The critical
  comparison is A versus B.

### Production acceptance rubric (proposed internal spec, 100 points)

| Category | Points | Measurable acceptance check |
|---|---|---|
| Silhouette / identity | 15 | Identifiable in black; pose intention understandable without face; acting hand not merged into torso |
| Shape design | 15 | Clear large/medium/small hierarchy; cast members differ in primary masses; no equal-width/equal-spacing rhythm |
| Construction | 10 | Stable limb lengths unless cheated deliberately; clean elbows/knees; no tube-like kinks; 3/4 forms volumetric |
| Face | 10 | Eight expressions distinguishable at delivery size; gaze unambiguous; speaking does not erase emotion |
| Hands / props / feet | 10 | Clean wrist transition; readable palm direction; props visibly contacted; planted foot supports the claimed weight |
| Pose / acting | 15 | One dominant line of action; no twinning; clear weight leg; deliberate counterpose; the pose states the thought |
| Line quality | 5 | Outer/internal hierarchy; no accidental tangencies; no auto-generated joins; no internal clutter |
| Color / value | 10 | Reads in grayscale; face/hands keep local emphasis; silhouette separated over ~90% of important perimeter |
| Lighting / texture | 5 | Shadow/rim agree with scene light; no universal halo; grain scale coherent with environment |
| Model consistency | 5 | Turnaround and poses stay on-model; anchors do not drift; replacement shapes keep identity |

Ship threshold: 85/100 overall, no category below 70% of its points. Four kill tests: silhouette test, grayscale test,
thumbnail test, no-effects test.

### What the AI coding agents should own

Own: SVG import/export cleanup preserving IDs; layer-name validation; pivot-marker extraction; rig JSON from authored
anchors; interpolation and spring plumbing; left/right transforms; pose serialization; grip transforms; viseme timing;
expression-state plumbing; contact sheets; silhouette and grayscale renders; pose thumbnail grids; bounding-box/tangent
warnings; missing-layer and off-model anchor tests; render comparisons; type-safe schemas; refactoring; background
extras from an approved design grammar.

Not own: final silhouette design; proportions from scratch; which Bézier feels more appealing; final hand drawings;
facial appeal; the hero pose; acting intent; "improving" approved asymmetry; adding complexity to satisfy "more
detailed"; final palette by numerical optimization alone.

Governing principle: proceduralize repetition, not taste.
