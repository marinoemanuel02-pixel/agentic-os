// Shared by the search adapters: license ids from the many ways sources write them (only the gate's allowlist
// survives; share-alike, non-commercial and no-derivatives become null and are dropped) and plain-text authors.
export const USER_AGENT = 'agentic-os-video-assets/1 (personal video pipeline)';

export function licenseFromUrl(url) {
  const u = String(url || '').toLowerCase();
  if (/publicdomain\/zero\//.test(u)) return 'cc0-1.0';
  if (/publicdomain\/mark\//.test(u)) return 'pd';
  const m = /\/licenses\/([a-z-]+)\/(\d\.\d)/.exec(u);
  if (m && m[1] === 'by' && (m[2] === '3.0' || m[2] === '4.0')) return `cc-by-${m[2]}`;
  return null;
}

export function licenseFromShort(text) {
  const t = String(text || '').trim().toLowerCase();
  if (t === 'cc0' || t === 'cc0 1.0' || t === 'cc-zero') return 'cc0-1.0';
  if (t === 'public domain' || t === 'pd' || t === 'pdm') return 'pd';
  const m = /^cc[ -]by[ -](\d\.\d)$/.exec(t);
  if (m && (m[1] === '3.0' || m[1] === '4.0')) return `cc-by-${m[1]}`;
  return null;
}

export const plain = html => String(html || '').replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();

export const query = params => new URLSearchParams(Object.entries(params).filter(([, v]) => v !== undefined && v !== null)).toString();

export function candidate(fields) {
  return {title: '', licenseUrl: null, duration: null, width: null, height: null, bytes: null, note: null, ...fields};
}
