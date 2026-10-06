// Pixabay (free key in the query string, as its API requires; 100 requests per 60 s; responses must be cached 24 h;
// no hotlinking; no bulk or automated collection: fetch only the items a director chose). Pixabay Content License.
import {candidate, query} from './common.mjs';

const LICENSE_URL = 'https://pixabay.com/service/license-summary/';

export default {
  id: 'pixabay',
  kinds: ['clip', 'photo'],
  needsKey: 'pixabay',
  async search(q, {kind, limit}, io) {
    const per_page = Math.max(3, Math.min(200, limit));
    if (kind === 'clip') {
      const j = await io.getJson(`https://pixabay.com/api/videos/?${query({key: io.key, q, per_page})}`);
      return (j.hits || []).map(h => {
        const f = [h.videos.large, h.videos.medium].find(x => x && x.url);
        if (!f) return null;
        return candidate({source: 'pixabay', id: String(h.id), kind, title: h.tags, page: h.pageURL, download: f.url, license: 'pixabay',
          licenseUrl: LICENSE_URL, author: h.user, credit: `Video by ${h.user} on Pixabay`, duration: h.duration, width: f.width, height: f.height, bytes: f.size || null});
      }).filter(Boolean).slice(0, limit);
    }
    const j = await io.getJson(`https://pixabay.com/api/?${query({key: io.key, q, image_type: 'photo', per_page})}`);
    return (j.hits || []).map(h => candidate({source: 'pixabay', id: String(h.id), kind, title: h.tags, page: h.pageURL, download: h.largeImageURL,
      license: 'pixabay', licenseUrl: LICENSE_URL, author: h.user, credit: `Photo by ${h.user} on Pixabay`, width: h.imageWidth, height: h.imageHeight})).slice(0, limit);
  },
};
