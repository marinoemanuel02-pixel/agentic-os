// Render a review sheet of the drawn cast straight to PNG, without Remotion: bundle a .tsx entry with esbuild, render
// its default export to static SVG with react-dom/server, rasterise with ImageMagick. Seconds per sheet, so character
// design can iterate. The entry default-exports a component that returns one <svg width height viewBox>.
//   node tools/toon-sheet.mjs <entry.tsx> <out.png>     (the cast sheet: tools/sheets/toon-cast.tsx)
// The kit lives in src/lib/toon/. Needs ImageMagick (`magick`) on PATH.
// Packages come from the render app's shared node_modules (TOON_NODE_MODULES overrides).
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { buildToon } from "./toon-build.mjs";

const [entry, out] = process.argv.slice(2);
if (!entry || !out) {
  console.error("usage: node tools/toon-sheet.mjs <entry.tsx> <out.png>");
  process.exit(2);
}
const nm = process.env.TOON_NODE_MODULES ?? join(homedir(), ".aos", "scratch", "video-agi-race", "node_modules");
const req = createRequire(join(nm, "noop.js"));
const esbuild = req("esbuild");
// next to the output (sandboxed agents may not write the system temp folder)
const dir = mkdtempSync(join(dirname(resolve(out)), ".toon-sheet-"));
const bundle = join(dir, "sheet.mjs");
// one bundle holds React, the renderer and the sheet, so hooks see a single React
await buildToon({
  stdin: {
    contents: `import React from "react"; import { renderToStaticMarkup } from "react-dom/server"; import Sheet from ${JSON.stringify(resolve(entry).split("\\").join("/"))}; export const render = () => renderToStaticMarkup(React.createElement(Sheet));`,
    resolveDir: process.cwd(),
    loader: "tsx",
  },
  bundle: true,
  platform: "node",
  format: "esm",
  jsx: "automatic",
  nodePaths: [nm],
  outfile: bundle,
  logLevel: "warning",
  banner: { js: `import { createRequire as __cr } from "node:module"; const require = __cr(${JSON.stringify(join(nm, "noop.js"))});` },
});
const mod = await import(pathToFileURL(bundle).href);
let svg = mod.render();
if (!svg.includes("xmlns=")) svg = svg.replace("<svg", '<svg xmlns="http://www.w3.org/2000/svg"');
const svgPath = resolve(out).replace(/\.png$/i, ".svg");
writeFileSync(svgPath, svg);
execFileSync("magick", ["-density", "96", svgPath, resolve(out)], { stdio: "inherit" });
console.log(`wrote ${out}`);
