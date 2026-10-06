// Where a film's heavy media lives, for CommonJS tools (make-voice.cjs): the same rule as tools/media-root.mjs.
// AOS_VIDEO_MEDIA_ROOT, else ~/.aos/video/<film folder name>; a git worktree resolves to its main checkout.
const fs = require("fs");
const os = require("os");
const path = require("path");

function filmName(projectDir) {
  const dir = path.resolve(projectDir);
  const git = path.join(dir, ".git");
  if (fs.existsSync(git) && fs.statSync(git).isFile()) {
    const m = /^gitdir:\s*(.+?)[\\/]\.git[\\/]worktrees[\\/][^\\/]+\s*$/m.exec(fs.readFileSync(git, "utf8"));
    if (m) return path.basename(m[1]);
  }
  return path.basename(dir);
}

function mediaRoot(projectDir) {
  if (process.env.AOS_VIDEO_MEDIA_ROOT) return path.resolve(process.env.AOS_VIDEO_MEDIA_ROOT);
  const name = filmName(projectDir);
  if (name.includes("{{") || fs.existsSync(path.join(path.resolve(projectDir), "_gitignore"))) {
    throw new Error("media root: refusing the template or an unsubstituted name; set AOS_VIDEO_MEDIA_ROOT");
  }
  return path.join(os.homedir(), ".aos", "video", name);
}

module.exports = { filmName, mediaRoot };
