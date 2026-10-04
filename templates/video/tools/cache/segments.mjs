// Split the edit into independently renderable segments: a hard cut starts a new segment; a dissolve ("x") joins
// its shot to the previous segment, because a dissolve mixes two shots' frames. Ranges are [from, to) in frames.
// Segments longer than `maxFrames` are split into chunks, each rendered by its own process: a long, heavy 3D shot
// rendered in one process went white after ~290 frames (alignment-now v6, S36), while the same frames in halves
// rendered correctly. Chunk boundaries are safe anywhere because the cache renders ranges of Main.
export function segments(shotBeats, beatFrames, maxFrames = Infinity) {
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
  const chunked = [];
  for (const seg of out) {
    for (let from = seg.from; from < seg.to; from += maxFrames) {
      chunked.push({from, to: Math.min(seg.to, from + maxFrames), shots: seg.shots});
    }
  }
  return chunked;
}
