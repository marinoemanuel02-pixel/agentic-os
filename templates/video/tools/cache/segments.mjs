// Split the edit into independently renderable segments: a hard cut starts a new segment; a dissolve ("x") joins
// its shot to the previous segment, because a dissolve mixes two shots' frames. Ranges are [from, to) in frames.
export function segments(shotBeats, beatFrames) {
  const out = [];
  let frame = 0;
  for (const [id, beats, transition] of shotBeats) {
    const frames = beats * beatFrames;
    if (transition === 'x' && out.length) {
      const last = out[out.length - 1];
      last.to += frames;
      last.shots.push(id);
    } else {
      out.push({from: frame, to: frame + frames, shots: [id]});
    }
    frame += frames;
  }
  return out;
}
