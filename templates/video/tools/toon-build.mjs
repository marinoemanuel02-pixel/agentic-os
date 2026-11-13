// Explicit file loading avoids esbuild walking unreadable ancestor directories in
// the desktop sandbox. Dependencies still resolve through the existing installation.
import { readFileSync, existsSync } from "node:fs";
import { createRequire, isBuiltin } from "node:module";
import { homedir } from "node:os";
import { dirname, extname, join, resolve } from "node:path";

export const toonModules = process.env.TOON_NODE_MODULES ?? join(homedir(), ".aos/scratch/video-agi-race/node_modules");
const req = createRequire(join(toonModules, "noop.js"));
export const buildToon = (options) => req("esbuild").build({
  bundle: true, platform: "node", format: "esm", jsx: "automatic", logLevel: "warning",
  banner: { js: `import {createRequire as __cr} from "node:module"; const require=__cr(${JSON.stringify(join(toonModules, "noop.js"))});` },
  ...options,
  plugins: [{
    name: "explicit-files",
    setup(build) {
      build.onResolve({ filter: /.*/ }, (args) => {
        if (isBuiltin(args.path)) return { path: args.path, external: true };
        const base = args.path.startsWith(".") || /^[A-Za-z]:/.test(args.path) || args.path.startsWith("/")
          ? resolve(args.resolveDir || process.cwd(), args.path)
          : req.resolve(args.path);
        const path = [base, ...[".tsx", ".ts", ".jsx", ".js", ".json", "/index.tsx", "/index.ts", "/index.js"].map((e) => base + e)]
          .find((p) => existsSync(p) && extname(p));
        if (!path) throw new Error(`Cannot resolve ${args.path} from ${args.resolveDir}`);
        return { path, namespace: "toon-file" };
      });
      build.onLoad({ filter: /.*/, namespace: "toon-file" }, (args) => ({
        contents: readFileSync(args.path, "utf8"), resolveDir: dirname(args.path),
        loader: ({ ".tsx": "tsx", ".ts": "ts", ".jsx": "jsx", ".json": "json" })[extname(args.path)] || "js",
      }));
    },
  }],
});
