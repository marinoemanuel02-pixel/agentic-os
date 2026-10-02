// The score's shape for tools/audio.mts: sections in beats (100 BPM, 1 beat = 0.6 s) and a chord loop (MIDI notes,
// two bars = 8 beats per chord). Move the section starts to the chapters of this video.
export const MUSIC = {
  sections: {
    pulse: 8, // sub pulse and hats start
    drive: 24, // kick on beats 1 and 3
    build: 32, // brighter pad, stronger pulse
    peak: 48, // arpeggio, the busiest section
    sparse: 64, // kick off, darker pad
    lift: 80, // final swell
    end: 92, // last hit, pad fades over 4 beats
  },
  chords: [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 49, 52]], // D minor: Dm Bb Gm A
};
