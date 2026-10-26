// Wikimedia Commons (no key; an identifying User-Agent is required). Keeps CC0, public domain and CC BY 3.0/4.0;
// CC BY-SA is dropped because share-alike may reach the whole film.
import {USER_AGENT, candidate, licenseFromShort, plain, query} from './common.mjs';

export default {
  id: 'wikimedia',
  kinds: ['photo', 'clip'],
  needsKey: null,
  async search(q, {kind, limit}, io) {
    const filetype = kind === 'clip' ? 'filetype:video' : 'filetype:bitmap';
    const url = `https://commons.wikimedia.org/w/api.php?${query({action: 'query', format: 'json', generator: 'search', gsrnamespace: 6,
      gsrsearch: `${q} ${filetype}`, gsrlimit: limit, prop: 'imageinfo', iiprop: 'url|size|mime|extmetadata'})}`;
    const j = await io.getJson(url, {'user-agent': USER_AGENT});
    return Object.values((j.query && j.query.pages) || {}).map(p => {
      const ii = (p.imageinfo || [])[0];
      if (!ii) return null;
      const meta = ii.extmetadata || {};
      const license = licenseFromShort(meta.LicenseShortName && meta.LicenseShortName.value);
      if (!license) return null;
      const author = plain(meta.Artist && meta.Artist.value) || 'unknown';
      const title = p.title.replace(/^File:/, '');
      return candidate({source: 'wikimedia', id: title, kind, title, page: ii.descriptionurl, download: ii.url, license,
        licenseUrl: (meta.LicenseUrl && meta.LicenseUrl.value) || null, author,
        credit: license === 'pd' || license === 'cc0-1.0' ? `${title} (Wikimedia Commons)` : `${title} by ${author}, ${meta.LicenseShortName.value} (Wikimedia Commons)`,
        width: ii.width || null, height: ii.height || null, bytes: ii.size || null});
    }).filter(Boolean);
  },
};
