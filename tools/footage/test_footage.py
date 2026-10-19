"""Offline footage acceptance tests; fixtures never touch personal media or models."""
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

try:
    import footage
except ModuleNotFoundError:
    footage = None


class FootageTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(footage, "footage CLI has not been implemented")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        for name in ("source", "cache", "exports"):
            (self.base / name).mkdir()
        self.roots = footage.Roots(self.base / "source", self.base / "cache", self.base / "exports")
        self.media = self.roots.source / "speech.mp4"
        self.media.write_bytes(b"original footage fixture")
        self.probe = patch.object(footage, "probe_media", return_value={
            "duration": 10.0, "has_video": True, "has_audio": True,
            "width": 160, "height": 90,
        })
        self.probe.start()
        self.addCleanup(self.probe.stop)

    def transcript(self):
        return {"schema": 1, "kind": "transcript", "source": footage.source_identity(self.roots, "speech.mp4"),
                "language": "en", "words": [
                    {"start": 1.0, "end": 1.4, "text": " Hello"},
                    {"start": 1.5, "end": 2.0, "text": " world"},
                    {"start": 5.0, "end": 5.5, "text": " Again"}]}

    def save_transcript(self):
        item = self.transcript()
        (self.roots.cache / "speech.json").write_text(json.dumps(item), encoding="utf-8")
        return item

    def test_inventory_records_relative_path_hash_and_streams(self):
        result = footage.inventory(self.roots)
        self.assertEqual(len(result["sources"]), 1)
        asset = result["sources"][0]
        self.assertEqual(asset["path"], "speech.mp4")
        self.assertEqual(asset["sha256"], hashlib.sha256(b"original footage fixture").hexdigest())
        self.assertEqual((asset["duration"], asset["has_audio"]), (10.0, True))

    def test_roots_and_relative_paths_cannot_write_among_sources(self):
        with self.assertRaises(footage.FootageError):
            footage.Roots(self.roots.source, self.roots.source / "cache", self.roots.output)
        for name in ("../escape.mp4", str(self.media), "C:\\elsewhere\\input.mp4", "https://example.invalid/a.mp4"):
            with self.subTest(name=name), self.assertRaises(footage.FootageError):
                footage.source_identity(self.roots, name)

    def test_symlink_source_escape_is_refused(self):
        outside = self.base / "outside.mp4"
        outside.write_bytes(b"outside")
        link = self.roots.source / "escape.mp4"
        try:
            link.symlink_to(outside)
        except OSError:
            self.skipTest("symlink creation unavailable")
        with self.assertRaises(footage.FootageError):
            footage.source_identity(self.roots, "escape.mp4")

    def test_search_returns_source_and_exact_match_interval(self):
        self.save_transcript()
        hits = footage.search(self.roots, ["speech.json"], "HELLO world")
        self.assertEqual(hits, [{"source": "speech.mp4", "start": 1.0, "end": 2.0, "text": "Hello world"}])

    def test_changed_source_invalidates_transcript_search_and_draft(self):
        self.save_transcript()
        self.media.write_bytes(b"changed footage fixture")
        with self.assertRaisesRegex(footage.FootageError, "changed|stale|hash"):
            footage.search(self.roots, ["speech.json"], "hello")
        with self.assertRaises(footage.FootageError):
            footage.draft_plan(self.roots, ["speech.json"], pad=0.2, min_gap=0.5)

    def test_draft_merges_speech_and_keeps_only_meaningful_silence(self):
        self.save_transcript()
        plan = footage.draft_plan(self.roots, ["speech.json"], pad=0.2, min_gap=0.5)
        self.assertFalse(plan["reviewed"])
        self.assertEqual([(cut["start"], cut["end"]) for cut in plan["cuts"]], [(0.8, 2.2), (4.8, 5.7)])
        self.assertEqual(plan["sources"][0]["path"], "speech.mp4")
        self.assertEqual(plan["sources"][0]["sha256"], self.transcript()["source"]["sha256"])

    def test_invalid_transcript_times_and_draft_options_are_refused(self):
        original = self.save_transcript()
        for start, end in ((-1, 1), (2, 1), (1, 11), (float("nan"), 2), (1, float("inf")), (True, 2)):
            item = copy.deepcopy(original)
            item["words"][0].update(start=start, end=end)
            (self.roots.cache / "bad.json").write_text(json.dumps(item), encoding="utf-8")
            with self.subTest(start=start, end=end), self.assertRaises(footage.FootageError):
                footage.search(self.roots, ["bad.json"], "hello")
        for pad, gap in ((-1, 0.5), (math.nan, 0.5), (0.2, math.inf), (0.2, -1)):
            with self.subTest(pad=pad, gap=gap), self.assertRaises(footage.FootageError):
                footage.draft_plan(self.roots, ["speech.json"], pad=pad, min_gap=gap)

    def test_plan_requires_review_and_valid_unique_bound_sources(self):
        self.save_transcript()
        plan = footage.draft_plan(self.roots, ["speech.json"], pad=0.2, min_gap=0.5)
        with self.assertRaisesRegex(footage.FootageError, "review"):
            footage.validate_plan(self.roots, plan)
        plan["reviewed"] = True
        footage.validate_plan(self.roots, plan)
        for mutation in (lambda p: p["cuts"][0].update(end=11),
                         lambda p: p["cuts"][0].update(start=math.nan),
                         lambda p: p["cuts"][0].update(source="../outside.mp4"),
                         lambda p: p["sources"].append(p["sources"][0]),
                         lambda p: p["sources"][0].update(sha256="0" * 64),
                         lambda p: p.update(reviewed="true")):
            bad = copy.deepcopy(plan)
            mutation(bad)
            with self.subTest(mutation=mutation), self.assertRaises(footage.FootageError):
                footage.validate_plan(self.roots, bad)

    def test_atomic_cache_write_never_replaces_destination(self):
        footage.write_json(self.roots.cache, "result.json", {"first": True})
        with self.assertRaises(footage.FootageError):
            footage.write_json(self.roots.cache, "result.json", {"second": True})
        self.assertEqual(json.loads((self.roots.cache / "result.json").read_text()), {"first": True})
        with self.assertRaises(footage.FootageError):
            footage.write_json(self.roots.cache, "../escape.json", {})
        self.assertFalse((self.base / "escape.json").exists())

    def test_transcription_requires_complete_existing_model_and_audio(self):
        model = self.base / "model"
        model.mkdir()
        with self.assertRaisesRegex(footage.FootageError, "model|tokenizer"):
            footage.transcribe(self.roots, "speech.mp4", model, sys.executable, "speech.json")
        for name in ("model.bin", "config.json", "tokenizer.json"):
            (model / name).write_text("{}", encoding="utf-8")
        with patch.object(footage, "probe_media", return_value={"duration": 10, "has_audio": False, "has_video": True, "width": 160, "height": 90}):
            with self.assertRaisesRegex(footage.FootageError, "audio"):
                footage.transcribe(self.roots, "speech.mp4", model, sys.executable, "speech.json")

    def test_local_whisper_runner_retains_words_and_forces_offline(self):
        model = self.base / "model"
        model.mkdir()
        for name in ("model.bin", "config.json", "tokenizer.json"):
            (model / name).write_text("{}", encoding="utf-8")
        # Boundary fixture exercises the actual runner without loading weights or using a network.
        fixture = self.base / "fixture"
        fixture.mkdir()
        (fixture / "faster_whisper.py").write_text('''
import os
from types import SimpleNamespace as NS
class WhisperModel:
    def __init__(self, path, **kwargs):
        assert os.path.isdir(path)
        assert kwargs['local_files_only'] is True
        assert kwargs['device'] == 'cpu'
        assert os.environ['HF_HUB_OFFLINE'] == '1'
        assert os.environ['TRANSFORMERS_OFFLINE'] == '1'
    def transcribe(self, path, **kwargs):
        assert kwargs['word_timestamps'] is True
        return iter([NS(words=[NS(start=1.0, end=1.4, word=' Hello'), NS(start=1.5, end=2.0, word=' world')])]), NS(language='en')
''', encoding="utf-8")
        with patch.dict(os.environ, {"PYTHONPATH": str(fixture)}):
            result = footage.transcribe(self.roots, "speech.mp4", model, sys.executable, "speech.json")
        self.assertEqual(result["words"][1], {"start": 1.5, "end": 2.0, "text": " world"})
        self.assertEqual(footage.search(self.roots, ["speech.json"], "hello")[0]["source"], "speech.mp4")


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg/FFprobe not installed")
class RenderIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(footage, "footage CLI has not been implemented")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        for name in ("source", "cache", "exports"):
            (self.base / name).mkdir()
        self.roots = footage.Roots(self.base / "source", self.base / "cache", self.base / "exports")
        self.media = self.roots.source / "generated.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=25:duration=4", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=4", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(self.media)], check=True, capture_output=True, encoding="utf-8", errors="replace", timeout=30)
        self.digest = hashlib.sha256(self.media.read_bytes()).hexdigest()

    def plan(self):
        return {"schema": 1, "kind": "cut-plan", "reviewed": True,
                "sources": [footage.source_identity(self.roots, "generated.mp4")],
                "cuts": [{"source": "generated.mp4", "start": 0.4, "end": 1.4}, {"source": "generated.mp4", "start": 2.0, "end": 3.2}]}

    def test_render_exact_cut_durations_streams_and_source_preservation(self):
        result = footage.render(self.roots, self.plan(), "final.mp4")
        probe = footage.probe_media(result)
        self.assertAlmostEqual(probe["duration"], 2.2, delta=0.1)
        self.assertTrue(probe["has_audio"] and probe["has_video"])
        raw = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(result)], check=True, capture_output=True, encoding="utf-8", errors="replace", timeout=30)
        streams = json.loads(raw.stdout)["streams"]
        self.assertEqual({s["codec_name"] for s in streams}, {"h264", "aac"})
        self.assertEqual(hashlib.sha256(self.media.read_bytes()).hexdigest(), self.digest)
        self.assertEqual(sorted(p.name for p in self.roots.output.iterdir()), ["final.mp4"])
        with self.assertRaises(footage.FootageError):
            footage.render(self.roots, self.plan(), "final.mp4")

    def test_changed_source_refuses_render_before_creating_export(self):
        plan = self.plan()
        with self.media.open("ab") as handle:
            handle.write(b"changed")
        with self.assertRaisesRegex(footage.FootageError, "changed|stale|hash"):
            footage.render(self.roots, plan, "stale.mp4")
        self.assertEqual(list(self.roots.output.iterdir()), [])

    def test_cli_pipeline_inventory_transcribe_search_review_render(self):
        model = self.base / "local-model"
        model.mkdir()
        for name in ("model.bin", "config.json", "tokenizer.json"):
            (model / name).write_text("{}", encoding="utf-8")
        fixture = self.base / "fixture"
        fixture.mkdir()
        (fixture / "faster_whisper.py").write_text("from types import SimpleNamespace as N\nclass WhisperModel:\n def __init__(self, path, **kwargs):\n  assert kwargs['local_files_only'] is True\n def transcribe(self, path, **kwargs):\n  return iter([N(words=[N(start=0.5, end=0.9, word=' Hello'), N(start=2.0, end=2.4, word=' again')])]), N(language='en')\n", encoding="utf-8")
        env = os.environ.copy()
        env["PYTHONPATH"] = str(fixture)
        cli = [sys.executable, str(Path(footage.__file__)), "--source-root", str(self.roots.source), "--cache-root", str(self.roots.cache), "--output-root", str(self.roots.output)]
        def call(*args, expected=0):
            result = subprocess.run([*cli, *args], capture_output=True, encoding="utf-8", errors="replace", env=env, timeout=30)
            self.assertEqual(result.returncode, expected, result.stderr)
            return json.loads(result.stdout) if expected == 0 else result.stderr
        listing = call("inventory", "--out", "inventory.json")
        self.assertEqual(listing["sources"][0]["sha256"], self.digest)
        transcript = call("transcribe", "generated.mp4", "--model-dir", str(model), "--whisper-python", sys.executable, "--out", "words.json")
        self.assertEqual(transcript["words"][0]["start"], 0.5)
        hits = call("search", "Hello", "words.json")
        self.assertEqual(hits, [{"source": "generated.mp4", "start": 0.5, "end": 0.9, "text": "Hello"}])
        plan = call("draft", "words.json", "--pad", "0.1", "--min-gap", "0.2", "--out", "draft.json")
        self.assertFalse(plan["reviewed"])
        self.assertIn("review", call("render", "draft.json", "--out", "unreviewed.mp4", expected=2))
        self.assertEqual(list(self.roots.output.iterdir()), [])
        plan["reviewed"] = True
        (self.roots.cache / "reviewed.json").write_text(json.dumps(plan), encoding="utf-8")
        call("render", "reviewed.json", "--out", "pipeline.mp4")
        self.assertAlmostEqual(footage.probe_media(self.roots.output / "pipeline.mp4")["duration"], 1.2, delta=0.1)
        self.assertEqual(hashlib.sha256(self.media.read_bytes()).hexdigest(), self.digest)

    def test_no_audio_video_refuses_export(self):
        silent = self.roots.source / "silent.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-f", "lavfi", "-i", "testsrc2=size=96x64:rate=15:duration=1", "-c:v", "libx264", str(silent)], check=True, capture_output=True, encoding="utf-8", errors="replace", timeout=30)
        plan = {"schema": 1, "kind": "cut-plan", "reviewed": True, "sources": [footage.source_identity(self.roots, "silent.mp4")], "cuts": [{"source": "silent.mp4", "start": 0, "end": 0.5}]}
        with self.assertRaisesRegex(footage.FootageError, "audio"):
            footage.render(self.roots, plan, "silent.mp4")
        self.assertEqual(list(self.roots.output.iterdir()), [])

    def test_audio_only_media_refuses_video_export(self):
        audio = self.roots.source / "audio.wav"
        subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-f", "lavfi", "-i", "sine=duration=1", str(audio)], check=True, capture_output=True, encoding="utf-8", errors="replace", timeout=30)
        plan = {"schema": 1, "kind": "cut-plan", "reviewed": True, "sources": [footage.source_identity(self.roots, "audio.wav")], "cuts": [{"source": "audio.wav", "start": 0, "end": 0.5}]}
        with self.assertRaisesRegex(footage.FootageError, "video|unsupported"):
            footage.render(self.roots, plan, "audio.mp4")
        self.assertEqual(list(self.roots.output.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
