// NASA Image and Video Library (no key). Generally public domain; commercial use must not imply endorsement, and
// logos, insignia and identifiable people need clearance: the director fills `subjects` and `clearance` in the ledger.
import {candidate, query} from './common.mjs';

const ORIG = {clip: ['video', 'mp4'], photo: ['image', 'jpg']};

export default {
  id: 'nasa',
  kinds: ['clip', 'photo'],
  needsKey: null,
  async search(q, {kind, limit}, io) {
    const [type, ext] = ORIG[kind];
    const j = await io.getJson(`https://images-api.nasa.gov/search?${query({q, media_type: type, page_size: limit})}`);
    return ((j.collection && j.collection.items) || []).slice(0, limit).map(item => {
      const d = item.data[0];
      return candidate({source: 'nasa', id: d.nasa_id, kind, title: d.title, page: `https://images.nasa.gov/details/${encodeURIComponent(d.nasa_id)}`,
        download: `https://images-assets.nasa.gov/${type}/${encodeURIComponent(d.nasa_id)}/${encodeURIComponent(d.nasa_id)}~orig.${ext}`,
        license: 'pd', licenseUrl: 'https://www.nasa.gov/nasa-brand-center/images-and-media/', author: `NASA/${d.center || 'unknown'}`,
        credit: `NASA/${d.center || 'unknown'}`, note: 'logos and identifiable people need clearance before use (set subjects and clearance)'});
    });
  },
};
