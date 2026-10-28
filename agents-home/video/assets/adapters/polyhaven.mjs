// Poly Haven (no key; CC0; its API asks for an identifying User-Agent and a visible "Powered by Poly Haven" credit,
// which credits.mjs adds). The API lists the whole catalogue per type; the query words are matched locally.
// The download is the files API for that asset (formats and resolutions); the director picks one.
import {USER_AGENT, candidate} from './common.mjs';

const TYPES = {model: 'models', hdri: 'hdris', texture: 'textures'};

export default {
  id: 'polyhaven',
  kinds: ['model', 'hdri', 'texture'],
  needsKey: null,
  async search(q, {kind, limit}, io) {
    const j = await io.getJson(`https://api.polyhaven.com/assets?t=${TYPES[kind]}`, {'user-agent': USER_AGENT});
    const words = q.toLowerCase().split(/\s+/).filter(Boolean);
    return Object.entries(j).filter(([id, a]) => {
      const hay = [id, a.name, ...(a.tags || []), ...(a.categories || [])].join(' ').toLowerCase();
      return words.some(w => hay.includes(w));
    }).slice(0, limit).map(([id, a]) => candidate({source: 'polyhaven', id, kind, title: a.name, page: `https://polyhaven.com/a/${id}`,
      download: `https://api.polyhaven.com/files/${id}`, license: 'cc0-1.0', licenseUrl: 'https://polyhaven.com/license',
      author: Object.keys(a.authors || {}).join(', ') || 'Poly Haven', credit: `Poly Haven: ${a.name}`,
      note: 'pick a format in the files list (models: a self-contained .glb, or convert .gltf)'}));
  },
};
