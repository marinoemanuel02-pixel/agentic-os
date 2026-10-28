"""Where a film's heavy media lives, for the Python tools: the same rule as tools/media-root.mjs.

AOS_VIDEO_MEDIA_ROOT, else ~/.aos/video/<film folder name>, where the film folder is the project folder or, for a git
worktree, its main checkout (read from the worktree's .git file). The template and unsubstituted names are refused.
"""
import os
import re
import sys
from pathlib import Path


def film_name(project: Path) -> str:
    git = project / ".git"
    if git.is_file():
        m = re.search(r"^gitdir:\s*(.+?)[\\/]\.git[\\/]worktrees[\\/][^\\/]+\s*$", git.read_text(encoding="utf-8"), re.M)
        if m:
            return Path(m.group(1)).name
    return project.name


def media_root(project: Path) -> Path:
    env = os.environ.get("AOS_VIDEO_MEDIA_ROOT")
    if env:
        return Path(env)
    name = film_name(project)
    if "{{" in name or (project / "_gitignore").exists():
        sys.exit("media root: refusing the template or an unsubstituted name; set AOS_VIDEO_MEDIA_ROOT")
    return Path.home() / ".aos" / "video" / name
