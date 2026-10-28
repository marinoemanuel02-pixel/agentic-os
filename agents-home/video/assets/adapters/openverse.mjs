// Openverse (no key; anonymous 20 per minute, 200 per day). Asks for commercial-and-modification licenses and keeps
// only CC0, public-domain mark and CC BY (no share-alike); results carry a ready attribution string.
import {candidate, licenseFromShort, query} from './common.mjs';

export default {
  id: 'openverse',
  kinds: ['photo'],
  needsKey: null,
  async search(q, {kind, limit}, io) {
    const j = await io.getJson(`https://api.openverse.org/v1/images/?${query({q, license_type: 'commercial,modification', page_size: limit})}`);
    return (j.results || []).map(r => {
      const short = r.license === 'cc0' ? 'cc0' : r.license === 'pdm' ? 'pd' : `cc by ${r.license_version}`;
      const license = r.license === 'by' || r.license === 'cc0' || r.license === 'pdm' ? licenseFromShort(short) : null;
      if (!license || !/^https:/.test(r.url)) return null;
      return candidate({source: 'openverse', id: r.id, kind, title: r.title, page: r.foreign_landing_url, download: r.url, license,
        licenseUrl: r.license_url, author: r.creator || 'unknown', credit: r.attribution, width: r.width, height: r.height});
    }).filter(Boolean);
  },
};
