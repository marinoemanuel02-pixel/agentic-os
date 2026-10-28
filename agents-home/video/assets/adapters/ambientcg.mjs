// ambientCG (no key; CC0 materials). The 2K JPG zip is the default download.
import {USER_AGENT, candidate, query} from './common.mjs';

export default {
  id: 'ambientcg',
  kinds: ['texture'],
  needsKey: null,
  async search(q, {kind, limit}, io) {
    const j = await io.getJson(`https://ambientcg.com/api/v2/full_json?${query({q, type: 'Material', include: 'downloadData', limit})}`, {'user-agent': USER_AGENT});
    return (j.foundAssets || []).map(a => {
      const zips = (((a.downloadFolders || {}).default || {}).downloadFiletypeCategories || {}).zip;
      const files = (zips && zips.downloads) || [];
      const f = files.find(x => x.attribute === '2K-JPG') || files[0];
      if (!f) return null;
      return candidate({source: 'ambientcg', id: a.assetId, kind, title: a.displayName || a.assetId, page: a.shortLink || `https://ambientcg.com/view?id=${a.assetId}`,
        download: f.downloadLink, license: 'cc0-1.0', licenseUrl: 'https://docs.ambientcg.com/license/', author: 'ambientCG',
        credit: `ambientCG: ${a.displayName || a.assetId}`, bytes: f.size || null});
    }).filter(Boolean).slice(0, limit);
  },
};
