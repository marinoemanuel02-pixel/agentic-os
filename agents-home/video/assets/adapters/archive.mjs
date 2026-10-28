// Internet Archive moving images (no key). The license comes only from an item's licenseurl: Prelinger and most
// collections are NOT blanket public domain, so an item without one is dropped. The download is the item's file list;
// the director picks the file there.
import {candidate, licenseFromUrl, query} from './common.mjs';

export default {
  id: 'archive',
  kinds: ['clip'],
  needsKey: null,
  async search(q, {kind, limit}, io) {
    const url = `https://archive.org/advancedsearch.php?${query({q: `${q} AND mediatype:movies`, rows: limit * 3, output: 'json'})}&fl[]=identifier&fl[]=title&fl[]=licenseurl&fl[]=rights`;
    const j = await io.getJson(url);
    return ((j.response && j.response.docs) || []).map(d => {
      const license = licenseFromUrl(d.licenseurl);
      if (!license) return null;
      return candidate({source: 'archive', id: d.identifier, kind, title: d.title, page: `https://archive.org/details/${d.identifier}`,
        download: `https://archive.org/download/${d.identifier}`, license, licenseUrl: d.licenseurl, author: d.title,
        credit: `${d.title} (Internet Archive)`, note: 'pick the video file in the item\'s download list'});
    }).filter(Boolean).slice(0, limit);
  },
};
