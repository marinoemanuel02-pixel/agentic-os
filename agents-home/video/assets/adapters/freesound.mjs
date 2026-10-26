// Freesound (free token, sent as "Authorization: Token <key>"; downloading originals needs OAuth2, so the HQ preview
// is the download). Keeps CC0 and CC BY; non-commercial sounds are dropped. Raw SFX can still draw Content ID claims.
import {candidate, licenseFromUrl, query} from './common.mjs';

export default {
  id: 'freesound',
  kinds: ['sfx'],
  needsKey: 'freesound',
  async search(q, {kind, limit}, io) {
    const url = `https://freesound.org/apiv2/search/text/?${query({query: q, filter: 'license:("Creative Commons 0" OR "Attribution")',
      fields: 'id,name,username,license,previews,url,duration', page_size: limit})}`;
    const j = await io.getJson(url, {authorization: `Token ${io.key}`});
    return (j.results || []).map(s => {
      const license = licenseFromUrl(s.license);
      const preview = s.previews && s.previews['preview-hq-mp3'];
      if (!license || !preview) return null;
      return candidate({source: 'freesound', id: String(s.id), kind, title: s.name, page: s.url, download: preview, license, licenseUrl: s.license,
        author: s.username, credit: `"${s.name}" by ${s.username} (freesound.org)`, duration: s.duration});
    }).filter(Boolean);
  },
};
