import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, mkdir, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { searchFiles, readText } from './aos-file-tools.ts';

test('reads an explicit outside-project path and limits text lines', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'aos-files-'));
  try {
    const path = join(dir, 'note.txt');
    await writeFile(path, 'caffè\nsecond\nthird');
    const result = await readText(path, 2);
    assert.equal(result.path, path);
    assert.equal(result.text, 'caffè\nsecond');
    assert.equal(result.truncated, true);
    await assert.rejects(readText(path, 0));
    await assert.rejects(readText(join(dir, 'missing.txt')));
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('skipped dependency folders do not stop searches and junctions are not followed', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'aos-files-'));
  try {
    await mkdir(join(dir, 'node_modules'));
    await mkdir(join(dir, 'work'));
    await mkdir(join(dir, 'outside'));
    await writeFile(join(dir, 'work', 'invoice-real.txt'), 'real');
    await writeFile(join(dir, 'outside', 'invoice-linked.txt'), 'linked');
    await symlink(join(dir, 'outside'), join(dir, 'work', 'linked'), 'junction');
    const result = await searchFiles(join(dir, 'work'), 'invoice');
    assert.equal(result.files.length, 1);
    assert.equal(result.files[0].path, join(dir, 'work', 'invoice-real.txt'));
    const all = await searchFiles(dir, 'invoice');
    assert.ok(all.files.some(f => f.path === join(dir, 'work', 'invoice-real.txt')));
    assert.equal(all.truncated, true);
    await assert.rejects(readText(join(dir, 'work')));
    await writeFile(join(dir, 'binary.dat'), Buffer.from([1, 0, 2]));
    await assert.rejects(readText(join(dir, 'binary.dat')), /Binary/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('search finds matching files with explicit result limits and cancellation', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'aos-files-'));
  try {
    await mkdir(join(dir, 'nested'));
    await writeFile(join(dir, 'invoice.txt'), 'a');
    await writeFile(join(dir, 'nested', 'invoice-2.txt'), 'b');
    await writeFile(join(dir, 'unrelated.txt'), 'c');
    const result = await searchFiles(dir, 'invoice', 1);
    assert.equal(result.files.length, 1);
    assert.equal(result.truncated, true);
    assert.ok(result.files[0].path.startsWith(dir));
    const controller = new AbortController(); controller.abort();
    await assert.rejects(searchFiles(dir, 'invoice', 5, controller.signal));
    await assert.rejects(searchFiles(dir, '', 5));
  } finally { await rm(dir, { recursive: true, force: true }); }
});
