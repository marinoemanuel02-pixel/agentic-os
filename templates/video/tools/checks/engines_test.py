"""render-shot.py with engine shots (tools/engines.py, R55-R57): frame-complete renders, preroll dropped, incremental
keys, a failed render never replaces a good clip, --repeat tells repeatable from noisy, hand-rendered imports, and the
command lines each real engine gets. A stand-in engine (fixtures/engines/fake_engine.py) writes the frames, so no
engine needs to be installed; the render cases need ffmpeg and are skipped without it.
Usage: python templates/video/tools/checks/engines_test.py"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
FAKE = Path(__file__).resolve().parent / "fixtures" / "engines" / "fake_engine.py"
sys.path.insert(0, str(TOOLS))
import engines  # noqa: E402

HAS_FFMPEG = shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None


class Film:
    """A throwaway film folder with the two render tools, an engine table and a private media root."""

    def __init__(self, shots: dict):
        self.dir = Path(tempfile.mkdtemp(prefix="engines-film-"))
        (self.dir / "tools").mkdir()
        for name in ("render-shot.py", "engines.py"):
            shutil.copy(TOOLS / name, self.dir / "tools" / name)
        (self.dir / "engines").mkdir()
        (self.dir / "engines" / "engines.json").write_text(json.dumps({"size": [64, 36], "fps": 30}), encoding="utf-8")
        (self.dir / "src" / "data").mkdir(parents=True)
        self.media = self.dir / "media"
        self.table(shots)

    def table(self, shots: dict):
        (self.dir / "engines" / "shots.json").write_text(json.dumps(shots), encoding="utf-8")

    def run(self, *args):
        env = {**os.environ, "AOS_VIDEO_MEDIA_ROOT": str(self.media), "PYTHON": sys.executable}
        return subprocess.run([sys.executable, str(self.dir / "tools" / "render-shot.py"), *args], capture_output=True,
                              text=True, encoding="utf-8", errors="replace", env=env)

    def clip(self, sid):
        return self.media / "app" / "public" / "clips" / f"{sid}.mp4"

    def media_row(self, sid):
        return json.loads((self.dir / "src" / "data" / "media.json").read_text(encoding="utf-8"))[sid]


def fake(mode="steady", frames=10, **extra):
    return {"engine": "cmd", "frames": frames, "inputs": ["engines/look.txt"],
            "cmd": ["{python}", str(FAKE), "{frames}", "{n}", "{w}", "{h}", mode], **extra}


def first_luma(clip: Path) -> float:
    r = subprocess.run(["ffmpeg", "-nostdin", "-v", "info", "-i", str(clip), "-vf", r"select=eq(n\,0),signalstats,metadata=print:key=lavfi.signalstats.YAVG",
                        "-frames:v", "1", "-f", "null", "-"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return float([l for l in r.stderr.splitlines() if "YAVG" in l][-1].split("=")[-1])


@unittest.skipUnless(HAS_FFMPEG, "ffmpeg/ffprobe are not on PATH")
class EngineRenders(unittest.TestCase):
    def setUp(self):
        self.film = Film({"S01": fake()})
        (self.film.dir / "engines" / "look.txt").write_text("v1", encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.film.dir, ignore_errors=True)

    def test_renders_frames_plus_handle_into_one_clip_and_records_the_engine(self):
        r = self.film.run("S01")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(engines.count(self.film.clip("S01")), 10 + 6)
        self.assertEqual(self.film.media_row("S01")["engine"], "cmd")
        log = (self.film.media / "renders" / "render-log.jsonl").read_text(encoding="utf-8")
        self.assertIn('"engine": "cmd"', log)

    def test_unchanged_inputs_skip_and_a_changed_input_renders_again(self):
        self.assertEqual(self.film.run("S01").returncode, 0)
        self.assertIn("unchanged", self.film.run("S01").stdout)
        (self.film.dir / "engines" / "look.txt").write_text("v2", encoding="utf-8")
        again = self.film.run("S01")
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertNotIn("unchanged", again.stdout)

    def test_a_changed_adapter_renders_again_and_a_cache_hit_restores_a_lost_media_row(self):
        # Codex review 2026-10-27: the key left out the adapter code, and a hit left a deleted media row missing
        self.assertEqual(self.film.run("S01").returncode, 0)
        media = self.film.dir / "src" / "data" / "media.json"
        media.write_text("{}", encoding="utf-8")
        hit = self.film.run("S01")
        self.assertIn("unchanged", hit.stdout)
        self.assertEqual(self.film.media_row("S01")["clip"], "clips/S01.mp4")
        adapter = self.film.dir / "tools" / "engines.py"
        adapter.write_text(adapter.read_text(encoding="utf-8") + "\n# changed\n", encoding="utf-8")
        self.assertNotIn("unchanged", self.film.run("S01").stdout)

    def test_repeat_needs_a_positive_frame_count(self):
        r = self.film.run("S01", "--repeat", "0")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("--repeat", r.stdout + r.stderr)

    def test_preroll_frames_are_rendered_then_dropped(self):
        self.film.table({"S01": fake(preroll=20)})
        r = self.film.run("S01")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(engines.count(self.film.clip("S01")), 16)
        # grey 100 + index: the clip starts on frame 20 (grey 120), not frame 0 (grey 100); Y = 16 + 219 * g / 255
        self.assertAlmostEqual(first_luma(self.film.clip("S01")), 16 + 219 * 120 / 255, delta=2)

    def test_a_short_render_fails_and_keeps_the_good_clip(self):
        self.assertEqual(self.film.run("S01").returncode, 0)
        good = self.film.clip("S01").read_bytes()
        self.film.table({"S01": fake("short")})
        r = self.film.run("S01")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("frames, the shot needs 16", r.stdout + r.stderr)
        self.assertEqual(self.film.clip("S01").read_bytes(), good)
        self.assertFalse((self.film.media / "app" / "public" / "clips" / "S01.partial.mp4").exists())

    def test_a_script_error_fails_the_render_even_when_the_engine_exits_0(self):
        # Godot 4.7 renders the bare scene and exits 0 when a shot script fails to parse (seen on the first S01 render)
        self.film.table({"S01": fake("scripterror", fail_on=["SCRIPT ERROR"])})
        r = self.film.run("S01")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("SCRIPT ERROR", r.stdout + r.stderr)
        self.assertFalse(self.film.clip("S01").exists())
        self.assertIn("SCRIPT ERROR", engines.FAIL_ON["godot"])

    def test_a_dark_graphic_shot_passes_the_exposure_gate_only_with_a_written_reason(self):
        self.film.table({"S01": fake("dark")})
        self.assertNotEqual(self.film.run("S01").returncode, 0)
        self.film.table({"S01": fake("dark", luma=[25, 225])})
        r = self.film.run("S01", "--force")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("luma_why", r.stdout + r.stderr)
        self.film.table({"S01": fake("dark", luma=[25, 225], luma_why="thin notation on the near-black look")})
        r = self.film.run("S01", "--force")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.film.media_row("S01")["luma"], {"range": [25, 225], "why": "thin notation on the near-black look"})

    def test_repeat_tells_a_repeatable_engine_from_a_noisy_one(self):
        r = self.film.run("S01", "--repeat", "4")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.film.media_row("S01")["determinism"]["level"], "pixel-identical")
        self.film.table({"S01": fake("random")})
        r = self.film.run("S01", "--repeat", "4")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        row = self.film.media_row("S01")["determinism"]
        self.assertEqual((row["level"], row["differ"]), ("differs", 4))

    def test_a_transparent_video_expands_to_every_frame_over_the_look_background(self):
        # Manim 0.22's png-sequence skips held frames (a 1 s wait wrote 1 PNG, not 30); its transparent mov keeps them
        mov = self.film.dir / "in.mov"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "color=c=black@0.0:s=64x36:r=30:d=1,format=argb",
                        "-c:v", "qtrle", str(mov)], check=True)
        frames = engines.expand(mov, self.film.dir / "expanded", "#ff0000")
        self.assertEqual(len(frames), 30)
        r = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", str(frames[0]), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                           capture_output=True, check=True)
        self.assertEqual(r.stdout[:3], b"\xff\x00\x00")

    def test_a_hand_rendered_clip_is_imported_trimmed_and_keyed_on_its_bytes(self):
        src = self.film.dir / "renders-in" / "cavalry.mp4"
        src.parent.mkdir()
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=64x36:rate=30:duration=2",
                        "-pix_fmt", "yuv420p", str(src)], check=True)
        self.film.table({"S02": {"engine": "import", "source": "renders-in/cavalry.mp4", "frames": 20, "preroll": 5}})
        r = self.film.run("S02")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(engines.count(self.film.clip("S02")), 26)
        self.assertIn("unchanged", self.film.run("S02").stdout)
        self.film.table({"S02": {"engine": "import", "source": "renders-in/cavalry.mp4", "frames": 60}})
        r = self.film.run("S02")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("the shot needs 66", r.stdout + r.stderr)


class EngineTable(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="engines-table-"))
        (self.root / "blender").mkdir()
        (self.root / "engines").mkdir()

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def put(self, rel, data):
        (self.root / rel).write_text(json.dumps(data), encoding="utf-8")

    def test_blender_entries_keep_their_spec_and_engines_join_them(self):
        self.put("blender/shots.json", {"S01": {"script": "s_a.py", "shot": "wide"}})
        self.put("engines/shots.json", {"S02": {"engine": "godot", "scene": "res://shots/s.tscn"}})
        table = engines.load_table(self.root)
        self.assertEqual(table["S01"], ("blender", {"script": "s_a.py", "shot": "wide"}))
        self.assertEqual(table["S02"][0], "godot")

    def test_a_shot_in_both_tables_or_an_unknown_engine_is_refused(self):
        self.put("blender/shots.json", {"S01": {"script": "s_a.py"}})
        self.put("engines/shots.json", {"S01": {"engine": "godot"}})
        self.assertRaisesRegex(ValueError, "both", engines.load_table, self.root)
        self.put("engines/shots.json", {"S02": {"engine": "touchdesigner"}})
        self.assertRaisesRegex(ValueError, "not one of", engines.load_table, self.root)

    def test_frames_sort_by_number_and_mixed_types_are_refused(self):
        for name in ("f10.png", "f2.png", "f1.png"):
            (self.root / name).write_bytes(b"x")
        self.assertEqual([p.name for p in engines.collect(self.root)], ["f1.png", "f2.png", "f10.png"])
        (self.root / "f3.exr").write_bytes(b"x")
        self.assertRaisesRegex(engines.RenderError, "mixed", engines.collect, self.root)

    def test_scaled_sizes_stay_even(self):
        self.assertEqual(engines.scaled([1080, 1920], 75), (810, 1440))
        self.assertEqual(engines.scaled([1920, 1080], 33), (634, 356))

    def test_a_missing_engine_names_its_variable_instead_of_guessing(self):
        os.environ["UNITY_PATH"] = str(self.root / "nope.exe")
        try:
            self.assertRaisesRegex(engines.RenderError, "UNITY_PATH", engines.executable, "unity")
        finally:
            del os.environ["UNITY_PATH"]


class EngineCommands(unittest.TestCase):
    """The flags each engine's documented headless render depends on (Godot 4.7 Movie Maker, Manim CE, MRQ, Recorder)."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="engines-cmd-"))
        self.exe = self.root / "engine.exe"
        self.exe.write_bytes(b"")
        self.saved = {k: os.environ.get(k) for k in ("GODOT_PATH", "MANIM_PATH", "UNREAL_CMD", "UNITY_PATH")}
        for k in self.saved:
            os.environ[k] = str(self.exe)

    def tearDown(self):
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(self.root, ignore_errors=True)

    def argv(self, engine, spec):
        return engines.command(self.root, engine, spec, self.root / "frames", 48, (1080, 1920), 30)

    def test_godot_runs_movie_maker_at_a_fixed_rate_for_exactly_the_frames_asked(self):
        argv, _, where = self.argv("godot", {"scene": "res://shots/s.tscn", "shot": "wide", "seed": 3})
        for flag in ("--write-movie", "--fixed-fps", "--quit-after", "res://shots/s.tscn"):
            self.assertIn(flag, argv)
        self.assertEqual(argv[argv.index("--quit-after") + 1], "48")
        self.assertEqual(argv[argv.index("--fixed-fps") + 1], "30")
        self.assertIn("--size=1080x1920", argv)
        self.assertIn("--seed=3", argv)
        self.assertEqual(where, self.root / "frames")

    def test_manim_writes_png_frames_at_the_film_size_with_tex_on_the_render_path_only(self):
        argv, env, _ = self.argv("manim", {"script": "s_attention.py", "scene": "Attention", "shot": "a"})
        # Manim 0.22: "png" saves only the last frame and "png-sequence" skips held frames; a transparent mov is
        # lossless (qtrle) and keeps every frame
        self.assertEqual(argv[argv.index("--format") + 1], "mov")
        self.assertIn("--transparent", argv)
        self.assertEqual(argv[argv.index("-r") + 1], "1080,1920")
        self.assertEqual((env["AOS_FRAMES"], env["AOS_SHOT"]), ("48", "a"))
        self.assertIn("PATH", env)

    def test_unreal_and_unity_render_unattended_from_their_presets(self):
        argv, _, where = self.argv("unreal", {"uproject": "u/F.uproject", "map": "/Game/M", "sequence": "/Game/S.S",
                                              "config": "/Game/R.R", "output": "u/Saved/S04"})
        for flag in ("-game", "-LevelSequence=/Game/S.S", "-MoviePipelineConfig=/Game/R.R", "-unattended"):
            self.assertIn(flag, argv)
        self.assertEqual(where, (self.root / "u/Saved/S04").resolve())
        argv, _, _ = self.argv("unity", {"project": "unity", "scene": "Assets/S.unity", "shot": "w"})
        self.assertEqual(argv[argv.index("-executeMethod") + 1], "AosRender.RenderShot")
        self.assertIn("-batchmode", argv)
        self.assertNotIn("-nographics", argv)


if __name__ == "__main__":
    unittest.main(verbosity=1)
