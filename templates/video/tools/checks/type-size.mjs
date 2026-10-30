// Type size (rubric 4, R58): no text under 36 px at 1080p. Reads every source file under src/lib and src/shots and
// checks the sizes written there: fontSize: 30 / fontSize={30} / fontSize="30px" / font-size="30" / font-size: 30px /
// the font shorthand (`500 26px ${SANS}`), also through a numeric constant of the same file (const SIZE = 84) and
// both branches of a ternary. Exit 1 on any size under the minimum.
//   node tools/checks/type-size.mjs [--min 36] [--root <film folder>]
// Sizes it cannot evaluate (props, em/rem, values from other files) are listed for frame review, and it cannot see a
// transform or viewBox that scales type, nor the world-unit height of 3D type (Tag.tsx): frames judge those (R14).
// huggingface-it v1 shipped quote-card source lines at 26-30 px; only a blind frame review found them.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const MIN_PX = 36;
const DIRS = ['src/lib', 'src/shots'];
const SOURCE = /\.(tsx?|jsx?|mts|mjs)$/;
const TYPE_WORDS = new Set(['number', 'string', 'any', 'unknown', 'undefined']);

// Comments become spaces (line breaks kept, so line numbers hold). Strings are copied whole, so "https://" is not a
// comment; a quote right after a letter is an apostrophe in JSX text, and a quoted string never spans lines.
const stripComments = (src) => {
  let out = '';
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    const next = src[i + 1];
    if ((c === '"' || c === "'" || c === '`') && !(c !== '`' && /[A-Za-z0-9]/.test(src[i - 1] || ''))) {
      let j = i + 1;
      while (j < src.length && src[j] !== c && !(c !== '`' && src[j] === '\n')) j += src[j] === '\\' ? 2 : 1;
      out += src.slice(i, j + 1);
      i = j + 1;
    } else if (c === '/' && next === '/') {
      while (i < src.length && src[i] !== '\n') { out += ' '; i++; }
    } else if (c === '/' && next === '*') {
      const end = src.indexOf('*/', i + 2);
      const stop = end < 0 ? src.length : end + 2;
      out += src.slice(i, stop).replace(/[^\n]/g, ' ');
      i = stop;
    } else {
      out += c;
      i++;
    }
  }
  return out;
};

// The expression that starts at `at`: up to a , ; } ) or line break outside brackets and strings.
const expressionAt = (src, at) => {
  let depth = 0;
  let i = at;
  while (i < src.length) {
    const c = src[i];
    if (c === '"' || c === "'" || c === '`') {
      let j = i + 1;
      while (j < src.length && src[j] !== c) j += src[j] === '\\' ? 2 : 1;
      i = j + 1;
      continue;
    }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) { if (depth === 0) break; depth--; }
    else if (depth === 0 && (c === ',' || c === ';' || c === '\n')) break;
    i++;
  }
  return src.slice(at, i).trim();
};

// The top-level `?` of a ternary and its matching `:`, or null.
const ternary = (expr) => {
  let depth = 0;
  let q = -1;
  let nested = 0;
  for (let i = 0; i < expr.length; i++) {
    const c = expr[i];
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    else if (depth === 0 && c === '?' && expr[i + 1] !== '.' && expr[i + 1] !== '?') {
      if (q < 0) q = i;
      else nested++;
    } else if (depth === 0 && c === ':' && q >= 0) {
      if (nested === 0) return [expr.slice(0, q), expr.slice(q + 1, i), expr.slice(i + 1)];
      nested--;
    }
  }
  return null;
};

const evaluate = (expr, consts) => {
  const t = ternary(expr);
  if (t) return [...evaluate(t[1].trim(), consts), ...evaluate(t[2].trim(), consts)];
  const quoted = /^(["'`])\s*(\d+(?:\.\d+)?)\s*(px)?\s*\1$/.exec(expr);
  if (quoted) return [Number(quoted[2])];
  if (/^["'`]/.test(expr)) return [null];
  let open = false;
  const arithmetic = expr.replace(/[A-Za-z_$][\w$]*/g, (name) => {
    if (name in consts) return String(consts[name]);
    open = true;
    return name;
  });
  if (open || !/^[\d.\s+\-*/()]+$/.test(arithmetic)) return [null];
  const value = Function(`"use strict"; return (${arithmetic});`)();
  return [Number.isFinite(value) ? value : null];
};

/** Every font size written in a source text: [{line, px (null when it cannot be evaluated), expr}]. */
export const sizesIn = (source) => {
  const src = stripComments(source);
  const lineAt = (at) => src.slice(0, at).split('\n').length;
  const consts = {};
  for (const m of src.matchAll(/(?:^|[^\w$.])const\s+([A-Za-z_$][\w$]*)\s*(?::\s*number\s*)?=\s*(-?\d+(?:\.\d+)?)\s*[;\n]/g)) consts[m[1]] = Number(m[2]);
  const found = [];
  const add = (at, expr) => {
    for (const px of evaluate(expr, consts)) found.push({at, line: lineAt(at), px, expr});
  };
  // fontSize: <expr> (style objects); fontSize?: is a type annotation and does not match
  for (const m of src.matchAll(/\bfontSize\s*:\s*/g)) {
    const expr = expressionAt(src, m.index + m[0].length);
    if (!TYPE_WORDS.has(expr)) add(m.index, expr);
  }
  // fontSize={<expr>} or fontSize="30" (JSX and SVG attributes)
  for (const m of src.matchAll(/\bfontSize\s*=\s*(\{|["'])/g)) {
    const start = m.index + m[0].length;
    if (m[1] === '{') add(m.index, expressionAt(src, start));
    else add(m.index, src.slice(start - 1, src.indexOf(m[1], start) + 1));
  }
  // font-size="30" (SVG) and font-size: 30px (CSS text)
  for (const m of src.matchAll(/font-size\s*[:=]\s*["']?\s*(\d+(?:\.\d+)?)(px)?/g)) found.push({at: m.index, line: lineAt(m.index), px: Number(m[1]), expr: m[0]});
  // font: `500 26px ${SANS}` (the shorthand); a shorthand without a px size says nothing about size
  for (const m of src.matchAll(/(?:^|[^\w$-])font\s*:\s*/g)) {
    const expr = expressionAt(src, m.index + m[0].length);
    const px = /(\d+(?:\.\d+)?)px/.exec(expr);
    if (px) found.push({at: m.index, line: lineAt(m.index), px: Number(px[1]), expr});
  }
  return found.sort((a, b) => a.at - b.at).map(({line, px, expr}) => ({line, px, expr}));
};

const walk = (dir) => {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap((e) => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? walk(p) : SOURCE.test(e.name) ? [p] : [];
  });
};

/** Sizes under `min` and sizes that could not be evaluated, in src/lib and src/shots of a film folder. */
export const checkFilm = (root, min = MIN_PX) => {
  const files = DIRS.flatMap((d) => walk(path.join(root, d)));
  const small = [];
  const unresolved = [];
  for (const f of files) {
    const file = path.relative(root, f).split(path.sep).join('/');
    for (const s of sizesIn(fs.readFileSync(f, 'utf8'))) {
      if (s.px === null) unresolved.push({file, ...s});
      else if (s.px < min) small.push({file, ...s});
    }
  }
  return {small, unresolved, checked: files.length};
};

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const opt = (name, fallback) => (args.includes(name) ? args[args.indexOf(name) + 1] : fallback);
  const root = path.resolve(opt('--root', path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..')));
  const min = Number(opt('--min', MIN_PX));
  const r = checkFilm(root, min);
  for (const s of r.unresolved) console.log(`review in frames: ${s.file}:${s.line} font size ${s.expr} (not evaluated here)`);
  for (const s of r.small) console.error(`${s.file}:${s.line} ${s.px} px is under ${min} px (rubric 4, at 1080p)`);
  if (r.small.length) {
    console.error(`type-size: ${r.small.length} size(s) under ${min} px in ${DIRS.join(' and ')}`);
    process.exit(1);
  }
  console.log(`type-size: every size in ${DIRS.join(' and ')} is at least ${min} px (${r.checked} files, ${r.unresolved.length} to review in frames)`);
}
