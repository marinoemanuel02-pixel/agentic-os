// Every string the film puts on screen must be in the claims ledger (claims.json "screen"[].texts), and every
// ledger string must still be on screen. A coverage gate, not a fact checker: each entry's sources and kind are
// reviewed by a person or an agent. Exit 1 on any gap.
//   node tools/checks/screen-text.mjs
// On-screen strings are found in the shot files (src/shots/*.tsx) as:
//   text: "..." / text="..." (headlines, sublines, callouts, source lines, closing text), and
//   printed labels: all-capital string literals in authored shot/library files, plus literal JSX children.
// Screen text must be a literal in one of these forms; `text: someVariable` fails, so nothing escapes review.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Author text as literal text properties/attributes or JSX children. Computed text is rejected.
const STR = /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`[^`$]*`/.source;
const literal = value => value[0] === '"' ? JSON.parse(value) : value.slice(1, -1).replace(/\\(['\\])/g, '$1');
// A quote right after a word is an apostrophe in nested JSX text (agent's): no JS string starts there, except after
// a keyword such as return'}' or typeof"x" (Codex review).
const KEYWORDS = new Set(['return', 'typeof', 'case', 'in', 'of', 'void', 'yield', 'await', 'delete', 'throw', 'else', 'do', 'instanceof', 'new']);
const apostrophe = (source, at) => {
  if (source[at] === '`') return false;
  const word = /[A-Za-z0-9_$]+$/.exec(source.slice(Math.max(0, at - 12), at));
  return Boolean(word) && !KEYWORDS.has(word[0]);
};
// Track JSX nesting and balanced attribute expressions instead of interpreting every JS > as a tag end.
const jsxChildren = source => {
  const texts = new Set(), errors = [];
  const visit = source => {
    const stack = [];
    const quoted = at => {
      const quote = source[at++];
      while (at < source.length) {
        if (source[at] === '\\') at += 2;
        else if (source[at++] === quote) return at;
      }
      return at;
    };
    const braces = at => {
      let depth = 1;
      for (at++; at < source.length && depth; at++) {
        if ('"\'`'.includes(source[at]) && !apostrophe(source, at)) at = quoted(at) - 1;
        else if (source.slice(at, at + 2) === '/*') at = source.indexOf('*/', at + 2) < 0 ? source.length : source.indexOf('*/', at + 2) + 1;
        else if (source[at] === '{') depth++;
        else if (source[at] === '}') depth--;
      }
      return at;
    };
    for (let at = 0; at < source.length;) {
      if (!stack.length && '"\'`'.includes(source[at])) {at = quoted(at); continue;}
      if (!stack.length && source.slice(at, at + 2) === '//') {at = source.indexOf('\n', at + 2); if (at < 0) break; continue;}
      if (!stack.length && source.slice(at, at + 2) === '/*') {const end = source.indexOf('*/', at + 2); at = end < 0 ? source.length : end + 2; continue;}
      if (source[at] === '<') {
        const tag = source.slice(at).match(/^<(\/?)((?:[A-Za-z][\w.:-]*)(?=[\s/>])|(?=>))/);
        if (tag) {
          const name = tag[2], closing = !!tag[1];
          let end = at + tag[0].length;
          while (end < source.length && source[end] !== '>') {
            if ('"\'`'.includes(source[end])) end = quoted(end);
            else if (source[end] === '{') {const stop = braces(end); visit(source.slice(end + 1, stop - 1)); end = stop;}
            else end++;
          }
          if (end >= source.length) {errors.push('unclosed JSX tag'); break;}
          const selfClosing = source[end - 1] === '/';
          // A root needs a matching closing tag; comparisons and TS type parameters are not JSX roots.
          const close = '</' + name + '>';
          const rootHasClose = source.slice(end + 1).includes(close) ||
            (name && new RegExp('</' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*>').test(source.slice(end + 1)));
          if (closing) {
            if (stack.at(-1) === name) stack.pop();
            else if (stack.length) errors.push('mismatched JSX closing tag: ' + name);
          } else if (!selfClosing && (stack.length || rootHasClose)) stack.push(name);
          at = end + 1;
          continue;
        }
      }
      if (stack.length && source[at] === '{') {
        const end = braces(at), value = source.slice(at + 1, end - 1).trim();
        if (new RegExp(`^(?:${STR})$`).test(value)) texts.add(literal(value));
        else if (value && value !== 'children' && !/^\/\*[\s\S]*\*\/$/.test(value)) {
          visit(value);
          if (/^(Reveal|Label|div|span|p|h[1-6]|b|i|strong|em|small|a|button|label|li|td|th)$/.test(stack.at(-1))) errors.push('computed screen text: ' + value);
        }
        at = end; continue;
      }
      if (stack.length && !['<', '{'].includes(source[at])) {
        let end = at + 1;
        while (end < source.length && !['<', '{'].includes(source[end])) end++;
        const text = source.slice(at, end).replace(/\s+/g, ' ').trim();
        if (text) texts.add(text);
        at = end;
      } else at++;
    }
    if (stack.length) errors.push('unclosed JSX children: ' + stack.join('/'));
  };
  visit(source);
  return {texts, errors};
};
export function extract(source, {labelsOnly = false} = {}) {
  const texts = new Set(), errors = [];
  source = source.replace(/\bcue\([^)]*\)/g, '');
  const values = new RegExp(String.raw`\btext(?::\s*|=\s*)\{?\s*(${STR})`, 'g');
  if (!labelsOnly) {
    for (const m of source.matchAll(values)) texts.add(literal(m[1]));
    for (const m of source.matchAll(/\btext(?::\s*|=\s*)\{?\s*([A-Za-z_$][\w$.]*)/g)) {
      if (!['string', 'number'].includes(m[1])) errors.push(`non-literal screen text: text: ${m[1]}`);
    }
    for (const m of source.matchAll(/\btext(?::\s*|=\s*)\{?\s*`[^`]*\$\{/g)) errors.push(`computed screen text: ${m[0]}...`);
    const children = jsxChildren(source);
    children.texts.forEach(text => texts.add(text));
    errors.push(...children.errors);
  }
  for (const m of source.matchAll(/['"]([A-Z0-9][A-Z0-9 '?.:%-]*[A-Z0-9?.])['"]/g)) {
    if (/[A-Z]/.test(m[1]) && !/^[A-Z]\d+$/.test(m[1])) texts.add(m[1]);
  }
  return {texts, errors};
}

export function checkCoverage(onScreen, ledger) {
  const listed = new Set((ledger.screen ?? []).flatMap((e) => e.texts ?? []));
  const errors = [];
  for (const t of onScreen) if (!listed.has(t)) errors.push(`on screen but not in claims.json: "${t}"`);
  for (const t of listed) if (!onScreen.has(t)) errors.push(`in claims.json but not on screen: "${t}"`);
  for (const e of ledger.screen ?? []) if (!e.reviewed || !e.kind) errors.push(`unreviewed screen entry: ${(e.texts ?? [])[0]}`);
  return errors;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  // Scan authored shot/library JSX recursively; reusable text plumbing forwards props without authoring them.
  // The media components (R35) show only the ledger's source credit, which aos asset registry writes into claims.json
  // as generated label entries, so their forwarded text is covered there.
  const plumbing = new Set(['src/lib/Tag.tsx', 'src/lib/Type.tsx', 'src/lib/Stage.tsx', 'src/shots/kit.tsx',
    'src/lib/media/SourceTag.tsx', 'src/lib/media/Clip.tsx', 'src/lib/media/Photo.tsx', 'src/lib/media/Capture.tsx', 'src/lib/media/GlTransition.tsx']);
  const files = [];
  const walk = dir => {
    if (!fs.existsSync(dir)) return;
    for (const e of fs.readdirSync(dir, {withFileTypes: true})) {
      const f = path.join(dir, e.name);
      if (e.isDirectory()) walk(f);
      else if (e.name.endsWith('.tsx')) files.push(f);
    }
  };
  walk(path.join(root, 'src/shots')); walk(path.join(root, 'src/lib'));
  const onScreen = new Set(), errors = [];
  for (const f of files) {
    const relative = path.relative(root, f).replaceAll('\\', '/');
    if (plumbing.has(relative)) continue; // these stock helpers forward text; author words in shot/library consumers
    const r = extract(fs.readFileSync(f, 'utf8'));
    r.texts.forEach(t => onScreen.add(t));
    errors.push(...r.errors.map(e => `${relative}: ${e}`));
  }
  errors.push(...checkCoverage(onScreen, JSON.parse(fs.readFileSync(path.join(root, 'claims.json'), 'utf8'))));
  for (const e of errors) console.error('FAIL ' + e);
  if (errors.length) process.exit(1);
  console.log(`PASS: ${onScreen.size} on-screen strings, each in the claims ledger (truth judged by review, not here)`);
}
