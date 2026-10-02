// Copied into ~/.aos/video/{{name}}/app by tools/sync-app.sh. The app folder holds node_modules (a junction to
// the shared Remotion install) and a junction to this project's src/, so code stays in OneDrive and heavy files do not.
import { Config } from "@remotion/cli/config";
import path from "path";

const modules = path.join(process.cwd(), "node_modules");
Config.overrideWebpackConfig((c) => ({
  ...c,
  resolve: { ...c.resolve, modules: [modules, "node_modules"] },
}));
Config.setChromiumOpenGlRenderer("angle");
Config.setVideoImageFormat("jpeg");
Config.setJpegQuality(95);
