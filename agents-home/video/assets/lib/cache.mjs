// Content-addressed objects shared by every film, plus an index by URL. Builds only read it.
import {copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync} from 'node:fs';
import {extname, join} from 'node:path';
import {cacheRoot} from './paths.mjs';
import {sha256File} from './proxy.mjs';

const indexPath = () => join(cacheRoot(), 'index.json');
const readIndex = () => (existsSync(indexPath()) ? JSON.parse(readFileSync(indexPath(), 'utf8')) : {schema: 1, byUrl: {}});

export function storeObject(file, {url, retrieved, license = null}) {
  const sha256 = sha256File(file);
  const dir = join(cacheRoot(), 'objects');
  mkdirSync(dir, {recursive: true});
  const path = join(dir, sha256 + (extname(file).toLowerCase() || '.bin'));
  if (!existsSync(path)) copyFileSync(file, path);
  const index = readIndex();
  index.byUrl[url] = {sha256, path, retrieved, license};
  const tmp = `${indexPath()}.${process.pid}.tmp`;
  writeFileSync(tmp, JSON.stringify(index, null, 1));
  renameSync(tmp, indexPath());
  return {sha256, path};
}

export function lookupUrl(url) {
  const hit = readIndex().byUrl[url];
  return hit && existsSync(hit.path) ? hit : null;
}
