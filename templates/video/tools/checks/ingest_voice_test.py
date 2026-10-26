"""ingest-voice.py on a non-English narration (pauseai-it, Italian, 2026-10-27): the takes must be transcribed in the
narration's language (AOS_VO_LANG), and accented words must survive normalisation, or a line that starts with "È"
loses its first word. Runs without numpy or Whisper: both are stubbed.
Usage: python templates/video/tools/checks/ingest_voice_test.py"""
import importlib.util
import os
import sys
import types
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent.parent / "ingest-voice.py"


def load():
    np = types.ModuleType("numpy")
    np.ndarray = object
    np.float32 = "float32"
    np.frombuffer = lambda buf, dtype=None: buf
    sys.modules["numpy"] = np
    spec = importlib.util.spec_from_file_location("ingest_voice", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class IngestVoiceLanguage(unittest.TestCase):
    def setUp(self):
        self.mod = load()

    def test_accents_fold_to_their_base_letter(self):
        self.assertEqual(self.mod.norm("È"), "e")
        self.assertEqual(self.mod.norm("più"), "piu")
        self.assertEqual(self.mod.norm("dell’umanità"), "dell'umanita")
        self.assertEqual(self.mod.norm("Data,"), "data")

    def test_whisper_hears_the_narration_language(self):
        seen = {}

        class Model:
            def transcribe(self, audio, **kw):
                seen.update(kw)
                return [], None

        self.mod.subprocess = types.SimpleNamespace(run=lambda *a, **k: types.SimpleNamespace(stdout=b""))
        old = os.environ.get("AOS_VO_LANG")
        try:
            os.environ["AOS_VO_LANG"] = "it"
            self.mod.whisper_words(Path("x.wav"), "", Model())
            self.assertEqual(seen.get("language"), "it")
            del os.environ["AOS_VO_LANG"]
            self.mod.whisper_words(Path("x.wav"), "", Model())
            self.assertEqual(seen.get("language"), "en", "English stays the default")
        finally:
            if old is None:
                os.environ.pop("AOS_VO_LANG", None)
            else:
                os.environ["AOS_VO_LANG"] = old


if __name__ == "__main__":
    # report on stdout: Windows PowerShell 5.1 turns native stderr into an error record under $ErrorActionPreference Stop
    unittest.main(testRunner=unittest.TextTestRunner(stream=sys.stdout))
