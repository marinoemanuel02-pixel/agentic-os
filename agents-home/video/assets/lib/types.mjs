// Shared shapes (JSDoc only). A search adapter returns Candidates; `aos asset fetch` turns a chosen one into a ledger row.
/**
 * @typedef {'clip'|'photo'|'model'|'hdri'|'texture'|'sfx'} Kind
 * @typedef {{source: string, id: string, kind: Kind, title: string, page: string, download: string,
 *   license: string|null, licenseUrl: string|null, author: string, credit: string,
 *   duration: number|null, width: number|null, height: number|null, bytes: number|null}} Candidate
 * @typedef {{getJson: (url: string, headers?: Record<string, string>) => Promise<any>, key: string|null}} SearchIo
 * @typedef {{id: string, kinds: Kind[], needsKey: string|null,
 *   search: (query: string, opts: {kind: Kind, limit: number}, io: SearchIo) => Promise<Candidate[]>}} Adapter
 */
export const KINDS = ['clip', 'photo', 'model', 'hdri', 'texture', 'sfx'];
