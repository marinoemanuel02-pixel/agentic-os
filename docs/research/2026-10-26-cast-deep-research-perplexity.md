<!-- Provenance: Perplexity Deep Research report, pasted by the operator on 2026-10-26 in answer to the
"Perplexity Deep Research" prompt written for the cast v2 work (studios, reusable systems, code-driven examples).
Kept as research input, not as a decision. Condensed: the report's findings and links are kept, its prose is
shortened. The report could not see the attached images. Its claims are its own; the ones the cast v2 plan relies on
are re-checked there (section "Claims checked"). -->

# Perplexity Deep Research: examples and pipelines for simple 2D humans (condensed)

**Headline.** SVG humans can look professional, but "generate an attractive person from arbitrary joint coordinates"
is much harder than "animate a well-designed SVG puppet". Recommended: authored vector artwork + a deliberately
limited pose/acting system + Remotion, not increasingly elaborate procedural anatomy.

## 1. Studios to study

| Studio | What to learn | Public pipeline evidence (as reported) |
|---|---|---|
| Duolingo ([shape language](https://blog.duolingo.com/shape-language-duolingos-art-style/), [character library internship](https://blog.duolingo.com/designing-new-characters-internship/), [Video Call with Lily](https://blog.duolingo.com/video-call/), [reshaping Duo](https://blog.duolingo.com/reshaping-duo/)) | Silhouette, proportions and shape rhythm before detail; characters built from simple geometric blocks then iterated; negative space, exaggeration, minimal detail; a small shape vocabulary producing recognisable individuals | Figma for illustration; Rive for animated characters; a Rive state machine drives Lily's mouth positions, expressions and camera ([Guido Rosso post](https://www.linkedin.com/posts/guidorosso_duolingos-video-call-feature-is-made-with-activity-7289451434058625024-_sTM), [Rive use cases](https://rive.app/use-cases/mobile-apps)) |
| Kurzgesagt ([1200 hours making-of](https://www.youtube.com/watch?v=uFk0mgljtns), [process](https://kurzgesagt.org/what-we-do?visit=videos), [bird rig breakdown](https://www.linkedin.com/posts/in-a-nutshell-kurzgesagt-gmbh_this-is-how-we-rigged-the-birb-and-built-activity-7187088659769118720)) | Humans as small graphic actors inside a coherent world: simplified masses, economical faces, readable gestures, colours that belong to the scene | Illustrator + After Effects; Duik Bassel for rigs; flat 2D plus 3D elements; meticulous manual animation |
| Rational Animations ([channel](https://www.youtube.com/@RationalAnimations); animators [Vaughn Oeth](https://www.linkedin.com/in/vaughn-oeth-4ba626201), [Jodi Kuchenbecker](https://www.linkedin.com/in/jodi-kuchenbecker-0a04a0144)) | Acting over geometry: emotional changes, head and torso attitudes, contrasting poses, gestures carrying the explanation; study key poses and transitions | Toon Boom Harmony for traditional and rigged 2D; frame-by-frame mixed with rigs; compositing in Harmony and After Effects (first-hand animator accounts, not an official spec) |
| Headspace / Moth ([Headspace Kids](https://www.moth.studio/projects/kids-headspace), [Marah Curran](https://www.marahcurran.com/animation/headspace-kids)) | Simplify more, not less: generous simple masses, economical faces, expressive whole-body action | Adobe Animate for that launch film (Nexus did other Headspace work) |
| Cub Studio ([Lottie character animation](https://www.cubstudio.com/lottie-character-animation), [Lottie animations](https://www.cubstudio.com/lottie-animations)) | Graphic appeal plus mechanical simplicity: a rig should make good posing easier, not decide the design | After Effects + Bodymovin; Joysticks 'n Sliders, Duik, RubberHose in examples |
| TED-Ed ([Great Wall of China](https://ed.ted.com/lessons/what-makes-the-great-wall-of-china-so-extraordinary-megan-campisi-and-pen-pen-chen)) | Study one film's character system, not a "TED-Ed style" | Animate CC on that film (credited animator) |
| OverSimplified ([American Revolution pt 1](https://www.youtube.com/watch?v=gzALIXcY4pg)) | Limited characters serving story: recognisable heads/costumes, readable expressions, staging, comic timing | After Effects and Photoshop (creator's description) |
| CGP Grey | Extreme abstraction; how much human detail an explanation needs | Historically Inkscape/Final Cut then After Effects (secondary sources) |
| Vox, The Infographics Show, Ninja Nerd, The Human Body OverSimplified | Lower relevance: hierarchy and repeatable flat systems; Ninja Nerd is not a human-character benchmark | Various Adobe tools; no rig pipelines verified |

Attribution boundary (the report's): evidence supports Harmony at Rational Animations, AE/Duik at Kurzgesagt, Animate
on specific Headspace/TED-Ed films, Rive at Duolingo; not Moho, Limber, Spine, Grease Pencil or Cavalry.

## 2. Reusable character systems

Modular is not rigged: libraries give interchangeable artwork, not skeletons and controls.

| System | Licence (as reported) | What it is | Fit |
|---|---|---|---|
| [Open Peeps](https://www.openpeeps.com/) ([creator page](https://www.pablostanley.com/work/open-peeps)) | CC0 | Hand-drawn-style vector people, interchangeable heads, expressions, bodies | Bootstrap candidate; its line irregularity is design, not error |
| [Humaaans](https://www.humaaans.com/) | CC0 | Mix-and-match bodies, hair, clothes, poses (SVG) | Assembly and limited posing; editorial style |
| [Open Doodles](https://www.opendoodles.com/about) | CC0 | Loose expressive drawings | Pose swaps and inserts |
| [Blush](https://blush.design/illustrations) | custom, no attribution; SVG export is Pro | multi-artist collections | one coherent collection, paid for SVG |
| [Storyset](https://storyset.com/terms) | attribution unless subscription; redistribution restricted | customisable illustrations | scene elements |
| [Kenney Toon Characters](https://kenney.nl/assets/toon-characters), [Shape Characters](https://kenney-assets.itch.io/shape-characters) | CC0 | game sprites, poses | abstract casts, feature swaps |
| [DiceBear Adventurer](https://www.dicebear.com/styles/adventurer/) | CC BY 4.0 (Lisa Wischofsky) | code-configurable avatars, portraits only | procedural assembly of authored choices; crowds, profiles |

Animated systems: Rive community [Girl](https://rive.app/marketplace/6147-13125-girl/) and
[Girl Walking](https://rive.app/marketplace/13839-29136-girl-walking/) (CC BY as labelled); LottieFiles (licence
nuances: Simple License assets vs plan terms); Live2D [Haru sample](https://www.live2d.com/en/learn/sample/haru/)
(custom sample terms); Spine [Spineboy](https://en.esotericsoftware.com/spine-examples-spineboy) (runtime licence is
not free). No paid human rig pack verified; OpenGameArt not verified.

## 3. Code-driven examples, ranked

1. Duolingo Lily (Rive state machine over authored art): separate identity, body behaviour, expression, speech.
2. Cub Studio Lottie characters (AE + Bodymovin): study authored rig and exported result separately.
3. Spineboy: authored skeleton with meshes, IK, constraints; layered aim over run.
4. [Pose Animator](https://github.com/yemount/pose-animator) ([SVG preparation](https://github.com/jzozaya/pose-animator-svg/blob/master/README.md)): an input SVG with an `illustration` group and a named `skeleton`; the skeleton deforms the vector art. Closest reference for SVG surface + skeleton.
5. [Darin Senneff's animated SVG avatar](https://codepen.io/dsenneff/details/2c3e5bc86b372d5424b00edaf4990173): gaze and face reacting to a few events.
6. Live2D Haru + [Web SDK samples](https://github.com/Live2D/CubismWebSamples): facial parameterisation, limited turns.
7. DiceBear + [style definitions](https://github.com/dicebear/styles): controlled variation of an authored vocabulary.
Also: [Motion by Dave, Rive character explorations](https://motionbydave.com/rive-character-explorations).

Lottie is a way to deliver authored animation (Remotion plays it, controls timing), not a puppet engine.

## 4. Blunt answer

Professional results need authored design decisions, not necessarily traditional drawing or a tablet; an artist can
author SVG shapes even by editing coordinates. Three approaches: a skeleton generating every contour (viable only for
a deliberately constrained style; poor default); authored SVG shapes (fully compatible with code); authored shapes
rigged and controlled by code (best fit). Change the division of labour: code manipulates approved design choices
more often than it invents anatomy. Tests to run first: silhouette before finish; one frozen pose (if the still is
rejected, postpone animation work); authored hand replacements; view-specific artwork (front, 3/4, profile); allow
exceptions (replacement drawings for extreme gestures); do not fix appeal with shading.

## 5. Free-tool pipeline ranking (the report's recommendation, not measured)

1. Inkscape-authored SVG parts → small custom puppet layer → Remotion.
2. Coherent CC0 artwork → cleaned SVG parts → Remotion (fastest experiment if illustration is the blocker).
3. Authored pose/expression library → code-timed swaps and transitions → Remotion (preferred emergency pipeline).
4. Blender cutout/Grease Pencil shots → rendered sequences → Remotion (later, for shot-specific deformation).
5. Krita-animated inserts → Remotion (exceptional beats).
Conditional: Rive → Remotion's Rive component (free export carries a Rive splash screen).
Licence traps: Rive free export splash; Remotion is free for individuals and organisations up to three people (check
eligibility).

Proposed first build: one character; front, 3/4, profile; five hand shapes; six expressions; a small mouth library;
8–12 approved storytelling poses; separate parts; explicit overlap decisions; approve with the director before more
automation. A narrow API: character, view, pose (selects an approved performance setup, not joint coordinates),
expression, gazeTarget, leftHand, rightHand, speechCue, actionTiming. One decisive experiment: the same short scene
three ways (current generator, one authored SVG puppet, a small set of illustrated pose swaps), judged separately on
still appeal, pose clarity, emotional clarity and motion.
