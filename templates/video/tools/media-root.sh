# Sourced after P is set to the project folder. Sets H: AOS_VIDEO_MEDIA_ROOT, else ~/.aos/video/<film folder name>, where
# the film folder is P or, for a git worktree, its main checkout (from P/.git). Same rule as tools/media-root.mjs.
# Refuses the template (it has _gitignore) and unsubstituted names with exit 2, so nothing writes ~/.aos/video/{{name}}.
if [ -n "${AOS_VIDEO_MEDIA_ROOT:-}" ]; then H="$AOS_VIDEO_MEDIA_ROOT"
else
  _mr_name="$(basename "$P")"
  if [ -f "$P/.git" ]; then
    _mr_main="$(sed -n 's#^gitdir:[[:space:]]*\(.*\)[\/]\.git[\/]worktrees[\/][^\/]*[[:space:]]*$#\1#p' "$P/.git" | head -1)"
    if [ -n "$_mr_main" ]; then _mr_name="$(basename "$_mr_main")"; fi
  fi
  case "$_mr_name" in *'{{'*) echo "media root: unsubstituted project name \"$_mr_name\"" >&2; exit 2;; esac
  if [ -f "$P/_gitignore" ]; then echo "media root: refusing the video template; set AOS_VIDEO_MEDIA_ROOT" >&2; exit 2; fi
  H="$HOME/.aos/video/$_mr_name"
fi
