// Content-addressed objects shared by every film, plus an index by key. An object is trusted only while its bytes
// still hash to its name; it is published by copy-then-rename, so an interrupted copy never sits at the final path.
// Keys are opaque hashes of the request (the full URL can carry credentials); the index keeps a sanitized URL.
import {copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {extname, join} from 'node:path';
import {cacheRoot} from './paths.mjs';
import {sha256File} from './proxy.mjs';

const indexPath = () => join(cacheRoot(), 'index.json');
const readIndex = () => (existsSync(indexPath()) ? JSON.parse(readFileSync(indexPath(), 'utf8')) : {schema: 1, byKey: {}});

export const cacheKey = request => createHash('sha256').update(String(request)).digest('hex');

export function storeObject(file, {key, url, retrieved, license = null}) {
  const sha256 = sha256File(file);
  const dir = join(cacheRoot(), 'objects');
  mkdirSync(dir, {recursive: true});
  const path = join(dir, sha256 + (extname(file).toLowerCase() || '.bin'));
  if (!existsSync(path) || sha256File(path) !== sha256) {
    const tmp = `${path}.${process.pid}.${Date.now()}.tmp`;
    copyFileSync(file, tmp);
    rmSync(path, {force: true});
    renameSync(tmp, path);
  }
  const index = readIndex();
  index.byKey = index.byKey || {};
  index.byKey[key || cacheKey(url)] = {sha256, path, url, retrieved, license};
  const tmpIndex = `${indexPath()}.${process.pid}.tmp`;
  writeFileSync(tmpIndex, JSON.stringify(index, null, 1));
  renameSync(tmpIndex, indexPath());
  return {sha256, path};
}

export function lookupKey(key) {
  const hit = (readIndex().byKey || {})[key];
  if (!hit || !existsSync(hit.path)) return null;
  return sha256File(hit.path) === hit.sha256 ? hit : null;
}

export const lookupUrl = url => lookupKey(cacheKey(url));
