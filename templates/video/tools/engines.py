"""Engine adapters for tools/render-shot.py: every engine renders a shot to frames, the frames become one clip.

Blender keeps its own path in render-shot.py (blender/shots.json). Other engines are listed in engines/shots.json:
  {"S04": {"engine": "godot", "scene": "res://shots/s_tokens.tscn", "shot": "wide", "seed": 7}}
Engines: godot (Movie Maker), manim (png frames), unreal (Movie Render Queue), unity (Recorder via
engines/unity/Editor/AosRender.cs), cmd (any command that writes numbered frames: Autograph, scripts), import (a clip
or frame folder rendered by hand: Cavalry, any GUI tool). Each render is frame-complete or it fails: the engine must
write preroll + n frames; the preroll is dropped. --repeat in render-shot measures whether a rerun is pixel-identical.
Unreal and Unity are scaffolds until their first spike (account installs): their command lines are documented, not
yet run on this machine.
"""
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

ENGINES = ("godot", "manim", "unreal", "unity", "cmd", "import")
FRAME_EXTS = (".png", ".exr")
# Output that means the shot did not run although the engine exited 0: Godot 4.7 renders the bare scene when a shot
# script fails to parse. A cmd shot adds its own with "fail_on".
FAIL_ON = {"godot": ("SCRIPT ERROR", "Failed to load script"), "manim": ("Traceback (most recent call last)",)}
HOME = Path.home()
PROGRAMS = Path(os.environ.get("ProgramFiles", Path.home().anchor + "Program Files"))  # resolved at run time


class RenderError(RuntimeError):
    pass


def load_table(root: Path) -> dict:
    """{shot: (engine, spec)} from blender/shots.json (engine "blender", spec unchanged) and engines/shots.json."""
    table = {}
    blender = root / "blender" / "shots.json"
    if blender.exists():
        for sid, spec in json.loads(blender.read_text(encoding="utf-8")).items():
            table[sid] = ("blender", spec)
    engines = root / "engines" / "shots.json"
    if engines.exists():
        for sid, spec in json.loads(engines.read_text(encoding="utf-8")).items():
            if sid in table:
                raise ValueError(f"{sid} is in both blender/shots.json and engines/shots.json")
            engine = spec.get("engine")
            if engine not in ENGINES:
                raise ValueError(f"{sid}: engine {engine!r} is not one of {', '.join(ENGINES)}")
            table[sid] = (engine, spec)
    return table


def settings(root: Path) -> dict:
    """engines/engines.json: {"size": [w, h], "fps": 30}; a film without it renders 1920x1080 at 30 fps."""
    f = root / "engines" / "engines.json"
    s = json.loads(f.read_text(encoding="utf-8")) if f.exists() else {}
    return {"size": s.get("size", [1920, 1080]), "fps": s.get("fps", 30)}


def scaled(size, scale: int) -> tuple:
    """Size at scale percent, rounded to even pixels (H.264 4:2:0 needs even sides)."""
    return tuple(max(2, round(v * scale / 100 / 2) * 2) for v in size)


def _first(pattern: str) -> str:
    hits = sorted(glob.glob(pattern, recursive=True))
    return hits[-1] if hits else ""


def executable(engine: str) -> str:
    """The engine's program: an environment variable wins, then the install location this machine uses."""
    found = {
        "godot": os.environ.get("GODOT_PATH") or _first(str(HOME / ".local/bin/godot/Godot_v*_win64_console.exe")),
        "manim": os.environ.get("MANIM_PATH") or _first(str(HOME / ".aos/venvs/manim/Scripts/manim.exe")),
        "unreal": os.environ.get("UNREAL_CMD") or _first(str(PROGRAMS / "Epic Games/UE_*/Engine/Binaries/Win64/UnrealEditor-Cmd.exe")),
        "unity": os.environ.get("UNITY_PATH") or _first(str(PROGRAMS / "Unity/Hub/Editor/*/Editor/Unity.exe")),
    }.get(engine, "")
    if engine in ("godot", "manim", "unreal", "unity") and not (found and Path(found).exists()):
        var = {"godot": "GODOT_PATH", "manim": "MANIM_PATH", "unreal": "UNREAL_CMD", "unity": "UNITY_PATH"}[engine]
        raise RenderError(f"{engine} is not installed here (set {var} to its program); installs need the user's OK")
    return found


def tex_bin() -> str:
    """TinyTeX's bin folder for Manim's MathTex, kept off the user PATH (passed to the render process only)."""
    return os.environ.get("AOS_TEX_BIN") or os.path.dirname(_first(str(HOME / ".aos/tinytex/**/bin/windows/tlmgr.bat")))


def input_files(root: Path, engine: str, spec: dict) -> list:
    """Files whose bytes decide the picture. Binary engine projects (Unreal, Unity) list theirs in spec["inputs"]."""
    files = []
    if engine == "godot":
        proj = root / "engines" / "godot"
        files = [p for p in proj.rglob("*") if p.is_file() and ".godot" not in p.relative_to(proj).parts]
    elif engine == "manim":
        files = sorted((root / "engines" / "manim").rglob("*.py"))
    elif engine == "import":
        src = root / spec["source"]
        files = sorted(p for p in src.rglob("*") if p.is_file()) if src.is_dir() else [src]
    files += [root / p for p in spec.get("inputs", [])]
    look = root / "engines" / "look.json"
    if engine != "import" and look.exists():
        files.append(look)
    return sorted(set(files))


_FFMPEG = []


def ffmpeg_version() -> str:
    if not _FFMPEG:
        r = subprocess.run(["ffmpeg", "-version"], capture_output=True, text=True, encoding="utf-8", errors="replace")
        _FFMPEG.append(r.stdout.splitlines()[0] if r.stdout else "")
    return _FFMPEG[0]


def render_key(root: Path, engine: str, spec: dict, size, fps: int) -> str:
    """Spec, size, rate, the engine program (name, size, mtime), ffmpeg's version, this adapter's own code and every
    input file's bytes: any of them changing renders the shot again."""
    h = hashlib.sha256()
    prog = executable(engine) if engine in ("godot", "manim", "unreal", "unity") else ""
    st = Path(prog).stat() if prog else None
    version = f"{Path(prog).name} {st.st_size} {st.st_mtime_ns}" if prog else ""
    h.update(json.dumps([engine, spec, list(size), fps, version, ffmpeg_version()], sort_keys=True).encode())
    h.update(hashlib.sha256(Path(__file__).read_bytes()).digest())
    for f in input_files(root, engine, spec):
        if not f.exists():
            raise RenderError(f"input {f} is missing")
        h.update(f.relative_to(root).as_posix().encode() if f.is_relative_to(root) else str(f).encode())
        h.update(hashlib.sha256(f.read_bytes()).digest())
    return h.hexdigest()


def command(root: Path, engine: str, spec: dict, frames: Path, total: int, size, fps: int):
    """(argv, extra env, folder the frames land in) for one render of `total` frames at `size`."""
    w, h = size
    shot = str(spec.get("shot", ""))
    if engine == "godot":
        argv = [executable("godot"), "--path", str(root / "engines" / "godot"), spec["scene"],
                "--write-movie", str(frames / "f.png"), "--fixed-fps", str(fps), "--quit-after", str(total),
                "--", f"--shot={shot}", f"--size={w}x{h}", f"--frames={total}", f"--seed={spec.get('seed', 1)}"]
        return argv, {}, frames
    if engine == "manim":
        # Manim 0.22's png-sequence skips held frames (a 1 s wait wrote 1 PNG); its transparent mov is lossless
        # (qtrle) and keeps every frame, so run_frames expands it over the look's background.
        argv = [executable("manim"), "render", str(root / "engines" / "manim" / spec["script"]), spec["scene"],
                "--format", "mov", "--transparent", "--fps", str(fps), "-r", f"{w},{h}", "--media_dir", str(frames / "m"),
                "--disable_caching", "--progress_bar", "none"]
        env = {"AOS_SHOT": shot, "AOS_FRAMES": str(total), "AOS_FPS": str(fps), "AOS_SEED": str(spec.get("seed", 1)),
               "PATH": tex_bin() + os.pathsep + os.environ.get("PATH", "")}
        return argv, env, frames / "m"  # short: Manim nests partial movies deep (Windows MAX_PATH)
    if engine == "unreal":
        # The Movie Render Queue preset (spec["config"]) fixes format, samples, warm-up and the output folder.
        argv = [executable("unreal"), spec["uproject"], spec["map"], "-game", f"-LevelSequence={spec['sequence']}",
                f"-MoviePipelineConfig={spec['config']}", "-windowed", f"-ResX={w}", f"-ResY={h}", "-unattended",
                "-nosplash", "-stdout", "-FullStdOutLogOutput", "-NoTextureStreaming"]
        return argv, {}, (root / spec["output"]).resolve()
    if engine == "unity":
        argv = [executable("unity"), "-batchmode", "-projectPath", str((root / spec["project"]).resolve()),
                "-executeMethod", "AosRender.RenderShot", "-logFile", "-", "-aosScene", spec["scene"],
                "-aosShot", shot, "-aosFrames", str(total), "-aosSize", f"{w}x{h}", "-aosFps", str(fps),
                "-aosOut", str(frames)]
        return argv, {}, frames
    if engine == "cmd":
        fill = {"frames": str(frames), "n": str(total), "w": str(w), "h": str(h), "fps": str(fps), "shot": shot,
                "root": str(root), "python": os.environ.get("PYTHON", "python")}
        return [a.format(**fill) for a in spec["cmd"]], {}, frames
    raise RenderError(f"no command for engine {engine}")


def collect(folder: Path) -> list:
    """Numbered frames anywhere under folder, in frame order; one extension only."""
    found = [p for p in folder.rglob("*") if p.suffix.lower() in FRAME_EXTS and p.is_file()]
    exts = {p.suffix.lower() for p in found}
    if len(exts) > 1:
        raise RenderError(f"mixed frame types in {folder}: {sorted(exts)}")
    num = lambda p: [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", p.relative_to(folder).as_posix())]
    return sorted(found, key=num)


def run_frames(root: Path, engine: str, spec: dict, work: Path, total: int, size, fps: int, log: Path) -> list:
    """Render `total` frames into a clean work folder and return them; fewer frames than asked is a failure."""
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    argv, env, where = command(root, engine, spec, work, total, size, fps)
    if engine == "unreal" and where.exists():
        shutil.rmtree(where)  # the preset writes here; stale frames from an older render must not count
    p = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env={**os.environ, **env}, cwd=str(root))
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(f"$ {' '.join(argv)}\n{p.stdout}\n{p.stderr}", encoding="utf-8")
    if p.returncode != 0:
        raise RenderError(f"{engine} exited {p.returncode}; log {log}\n{(p.stdout + p.stderr)[-2000:]}")
    said = p.stdout + p.stderr
    for pattern in (*FAIL_ON.get(engine, ()), *spec.get("fail_on", [])):
        if pattern in said:
            line = next(l for l in said.splitlines() if pattern in l)
            raise RenderError(f"{engine} reported {line.strip()!r}; log {log}")
    if engine == "manim":
        videos = [v for v in where.rglob("*.mov") if "partial_movie_files" not in v.parts]
        if len(videos) != 1:
            raise RenderError(f"manim wrote {len(videos)} movies under {where}, expected 1; log {log}")
        frames = expand(videos[0], work / "expanded", background(root, spec))
    else:
        frames = collect(where)
    if len(frames) < total:
        raise RenderError(f"{engine} wrote {len(frames)} frames, the shot needs {total}; log {log}")
    return frames[:total]


def background(root: Path, spec: dict) -> str:
    """The colour under a transparent render: spec["bg"], else the first look's bg from engines/look.json."""
    if spec.get("bg"):
        return spec["bg"]
    f = root / "engines" / "look.json"
    looks = json.loads(f.read_text(encoding="utf-8")).get("looks", {}) if f.exists() else {}
    return next(iter(looks.values()), {}).get("bg", "#000000")


def expand(video: Path, out: Path, bg: str) -> list:
    """Every frame of a (transparent) video as PNG, composited over bg; returns them in order."""
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate",
                        "-of", "csv=p=0", str(video)], capture_output=True, text=True, check=True)
    w, h, rate = r.stdout.strip().split(",")[:3]
    graph = f"color=c={bg}:s={w}x{h}:r={rate}[b];[b][0:v]overlay=shortest=1:format=auto,format=rgb24"
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(video), "-filter_complex", graph,
                    str(out / "f_%06d.png")], check=True)
    return collect(out)


def encode(frames: list, out: Path, fps: int, linear: bool) -> None:
    """Frames -> silent H.264 like the asset proxies (CRF 18, GOP = fps). EXR is scene-linear: one sRGB conversion."""
    seq = out.parent / (out.stem + ".seq")
    if seq.exists():
        shutil.rmtree(seq)
    seq.mkdir(parents=True)
    ext = frames[0].suffix.lower()
    for i, f in enumerate(frames):
        dst = seq / f"f_{i:06d}{ext}"
        try:
            os.link(f, dst)
        except OSError:
            shutil.copyfile(f, dst)
    pre = ["-apply_trc", "iec61966_2_1"] if ext == ".exr" and linear else []
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-framerate", str(fps), *pre, "-i", str(seq / f"f_%06d{ext}"),
                    "-c:v", "libx264", "-crf", "18", "-g", str(fps), "-pix_fmt", "yuv420p", "-an", "-movflags", "+faststart",
                    str(out)], check=True)
    shutil.rmtree(seq)


def import_clip(root: Path, spec: dict, out: Path, skip: int, n: int, fps: int, size) -> None:
    """A hand-rendered clip or frame folder (Cavalry, any GUI tool) trimmed to the shot: frames skip .. skip+n-1."""
    src = root / spec["source"]
    if src.is_dir():
        frames = collect(src)
        if len(frames) < skip + n:
            raise RenderError(f"{src} has {len(frames)} frames, the shot needs {skip + n}")
        encode(frames[skip:skip + n], out, fps, spec.get("color", "linear") == "linear")
        return
    w, h = size
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(src), "-vf",
                    rf"select=gte(n\,{skip}),setpts=N/({fps}*TB),fps={fps},scale={w}:{h}", "-frames:v", str(n),
                    "-c:v", "libx264", "-crf", "18", "-g", str(fps), "-pix_fmt", "yuv420p", "-an", str(out)], check=True)
    if count(out) < n:
        raise RenderError(f"{src} gave {count(out)} frames after skipping {skip}, the shot needs {n}")


def count(clip: Path) -> int:
    r = subprocess.run(["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0", "-show_entries",
                        "stream=nb_read_packets", "-of", "csv=p=0", str(clip)], capture_output=True, text=True)
    return int((r.stdout.strip().split(",")[0] or "0"))


def frame_md5s(frames: list) -> list:
    """MD5 of each decoded frame (pixels, not file bytes: encoders may stamp metadata)."""
    out = []
    for f in frames:
        r = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", str(f), "-f", "framemd5", "-"],
                           capture_output=True, text=True, check=True)
        out += [line.split(",")[-1].strip() for line in r.stdout.splitlines() if line and not line.startswith("#")]
    return out


def repeat(root: Path, engine: str, spec: dict, work: Path, k: int, preroll: int, size, fps: int) -> dict:
    """Render the first k frames twice; pixel-identical means every decoded frame matched (R57). Encoded bytes are
    not compared: the clip is encoded once from the frames."""
    if k < 1:
        raise RenderError(f"--repeat needs a positive frame count, got {k}")
    runs = []
    for i in (1, 2):
        frames = run_frames(root, engine, spec, work / f"repeat{i}", preroll + k, size, fps, work / f"repeat{i}.log")
        runs.append(frame_md5s(frames[preroll:]))
    differ = sum(1 for a, b in zip(*runs) if a != b)
    shutil.rmtree(work / "repeat1", ignore_errors=True)
    shutil.rmtree(work / "repeat2", ignore_errors=True)
    return {"level": "pixel-identical" if differ == 0 else "differs", "frames": k, "differ": differ}
