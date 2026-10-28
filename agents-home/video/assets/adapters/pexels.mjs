// Pexels (free key, sent as the Authorization header; 200 requests per hour). Pexels License: commercial use, no
// attribution required (we credit anyway), no resale of unaltered copies.
import {candidate, query} from './common.mjs';

const LICENSE_URL = 'https://www.pexels.com/license/';

export default {
  id: 'pexels',
  kinds: ['clip', 'photo'],
  needsKey: 'pexels',
  async search(q, {kind, limit}, io) {
    const headers = {authorization: io.key};
    if (kind === 'clip') {
      const j = await io.getJson(`https://api.pexels.com/videos/search?${query({query: q, per_page: limit})}`, headers);
      return (j.videos || []).map(v => {
        const files = (v.video_files || []).filter(f => f.height <= 1080 && /^https:/.test(f.link)).sort((a, b) => b.height - a.height);
        const f = files[0];
        if (!f) return null;
        return candidate({source: 'pexels', id: String(v.id), kind, title: v.url.split('/').filter(Boolean).pop(), page: v.url, download: f.link,
          license: 'pexels', licenseUrl: LICENSE_URL, author: v.user.name, credit: `Video by ${v.user.name} on Pexels`,
          duration: v.duration, width: f.width, height: f.height});
      }).filter(Boolean);
    }
    const j = await io.getJson(`https://api.pexels.com/v1/search?${query({query: q, per_page: limit})}`, headers);
    return (j.photos || []).map(p => candidate({source: 'pexels', id: String(p.id), kind, title: p.alt || String(p.id), page: p.url,
      download: p.src.large2x || p.src.original, license: 'pexels', licenseUrl: LICENSE_URL, author: p.photographer,
      credit: `Photo by ${p.photographer} on Pexels`, width: p.width, height: p.height}));
  },
};
