import { opendir, open, stat } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { homedir } from 'node:os';

function target(path: string): string {
  if (typeof path !== 'string' || !path.trim() || path.includes('\0')) throw new Error('An explicit non-empty path is required');
  return resolve(path.replace(/^~(?=[\\/]|$)/, homedir()));
}
function bound(value: number, max: number): number {
  if (!Number.isInteger(value) || value < 1 || value > max) throw new Error(`Limit must be an integer from 1 to ${max}`);
  return value;
}

export async function readText(path: string, lines = 50, signal?: AbortSignal) {
  const actual = target(path); bound(lines, 200); signal?.throwIfAborted();
  const handle = await open(actual, 'r');
  try {
    if (!(await handle.stat()).isFile()) throw new Error('Target is not a regular file');
    const buffer = Buffer.alloc(32769);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    signal?.throwIfAborted();
    if (buffer.subarray(0, bytesRead).includes(0)) throw new Error('Binary or UTF-16 file: use a document-specific reader');
    const content = buffer.subarray(0, Math.min(bytesRead, 32768)).toString('utf8').replace(/^\uFEFF/, '');
    const parts = content.split(/\r?\n/);
    return { path: actual, text: parts.slice(0, lines).join('\n'), truncated: bytesRead > 32768 || parts.length > lines };
  } finally { await handle.close(); }
}

export async function searchFiles(path: string, query: string, limit = 10, signal?: AbortSignal) {
  const root = target(path); bound(limit, 50);
  if (typeof query !== 'string' || !query.trim() || query.length > 120) throw new Error('Query must be 1-120 characters');
  signal?.throwIfAborted();
  if (!(await stat(root)).isDirectory()) throw new Error('Search root is not a directory');
  const files: { path: string }[] = [];
  const errors: { path: string; error: string }[] = [];
  const pending = [{ path: root, depth: 0 }];
  let scanned = 0; let truncated = false; let stopped = false;
  while (pending.length && !stopped) {
    signal?.throwIfAborted();
    const current = pending.shift()!;
    try {
      const directory = await opendir(current.path);
      for await (const entry of directory) {
        signal?.throwIfAborted();
        if (++scanned > 5000) { truncated = true; stopped = true; break; }
        const full = join(current.path, entry.name);
        if (entry.isSymbolicLink()) continue;
        if (entry.isDirectory()) {
          if (current.depth < 5 && !['.git', 'node_modules', '.venv'].includes(entry.name)) pending.push({ path: full, depth: current.depth + 1 });
          else truncated = true;
        } else if (entry.isFile() && entry.name.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())) {
          files.push({ path: full });
          if (files.length >= limit) { truncated = true; stopped = true; break; }
        }
      }
    } catch (error) {
      signal?.throwIfAborted();
      if (current.path === root) throw error;
      errors.push({ path: current.path, error: error instanceof Error ? error.message : String(error) });
    }
  }
  return { root, files, scanned: Math.min(scanned, 5000), truncated, errors: errors.slice(0, 10) };
}

export default function register(pi: { registerTool(tool: Record<string, unknown>): void }) {
  for (const name of ['file_search', 'text_read']) {
    pi.registerTool({ name, label: name === 'file_search' ? 'Find files' : 'Read text',
      description: name === 'file_search' ? 'Find files by name below an explicit folder. Bounded search; returns actual paths and coverage.' : 'Read up to 200 lines of a text file at an explicit Windows path. No shell needed.',
      parameters: { type: 'object', properties: { path: { type: 'string' }, ...(name === 'file_search' ? { query: { type: 'string' }, limit: { type: 'integer', minimum: 1, maximum: 50 } } : { lines: { type: 'integer', minimum: 1, maximum: 200 } }) }, required: name === 'file_search' ? ['path', 'query'] : ['path'], additionalProperties: false },
      async execute(_id: string, params: { path: string; query: string; limit?: number; lines?: number }, signal?: AbortSignal) {
        try {
          const result = name === 'file_search' ? await searchFiles(params.path, params.query, params.limit, signal) : await readText(params.path, params.lines, signal);
          return { content: [{ type: 'text', text: JSON.stringify(result) }], details: result };
        } catch (error) { return { isError: true, content: [{ type: 'text', text: `NOT COMPLETED: ${error instanceof Error ? error.message : String(error)}` }] }; }
      },
    });
  }
}
