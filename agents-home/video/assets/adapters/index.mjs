// Every search source behind one interface (see lib/types.mjs Adapter). searchAll asks the sources that serve the
// kind (or the named ones), skips keyed sources without a key and reports a failing source without losing the rest.
import pexels from './pexels.mjs';
import pixabay from './pixabay.mjs';
import openverse from './openverse.mjs';
import wikimedia from './wikimedia.mjs';
import nasa from './nasa.mjs';
import archive from './archive.mjs';
import polyhaven from './polyhaven.mjs';
import ambientcg from './ambientcg.mjs';
import freesound from './freesound.mjs';

export const ADAPTERS = [pexels, pixabay, openverse, wikimedia, nasa, archive, polyhaven, ambientcg, freesound];

export async function searchAll(q, {kind, limit = 8, sources}, io) {
  const chosen = ADAPTERS.filter(a => (sources && sources.length ? sources.includes(a.id) : a.kinds.includes(kind)));
  const candidates = [];
  const skipped = [];
  for (const a of chosen) {
    const key = a.needsKey ? process.env[`AOS_KEY_${a.needsKey.toUpperCase()}`] || null : null;
    if (a.needsKey && !key) { skipped.push({id: a.id, reason: `no key (aos secret set ${a.needsKey})`}); continue; }
    if (!a.kinds.includes(kind)) { skipped.push({id: a.id, reason: `serves ${a.kinds.join(', ')}, not ${kind}`}); continue; }
    try {
      candidates.push(...await a.search(q, {kind, limit}, {getJson: io.getJson, key}));
    } catch (e) {
      skipped.push({id: a.id, reason: e.message});
    }
  }
  return {candidates, skipped};
}
