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


class PhonePolish(unittest.TestCase):
    """--phone (pauseai-it, 2026-10-27): phone takes carry clicks far above the voice band; the chain must remove them."""

    def hf_rms(self, filters):
        import re
        import shutil
        import subprocess
        if not shutil.which("ffmpeg"):
            self.skipTest("ffmpeg is not on PATH")
        # a 1 kHz tone with a click every 100 ms, then everything above 11 kHz measured
        src = "sine=f=1000:d=2:sample_rate=48000[a];aevalsrc='if(lt(mod(t,0.1),0.0002),0.9,0)':d=2:s=48000[c];[a][c]amix=inputs=2:normalize=0"
        chain = (filters + "," if filters else "") + "highpass=f=11000,highpass=f=11000,astats=metadata=0"
        r = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-filter_complex", src + "," + chain, "-f", "null", "-"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        return float(re.findall(r"RMS level dB: (-?[\d.]+|-inf)", r.stderr)[-1].replace("-inf", "-200"))

    def test_phone_chain_removes_clicks_above_the_voice(self):
        mod = load()
        self.assertTrue(hasattr(mod, "PHONE_CHAIN"), "ingest-voice.py offers a --phone chain")
        self.assertNotIn("deesser", mod.PHONE_CHAIN, "the de-esser added broadband clicks")
        raw, polished = self.hf_rms(""), self.hf_rms(mod.PHONE_CHAIN)
        self.assertLess(polished, raw - 20, f"clicks above 11 kHz: {raw:.1f} dB raw, {polished:.1f} dB polished")


class VoiceEnd(unittest.TestCase):
    """pauseai-it L10, 2026-10-27: Whisper heard "cinquanta per cento" as one token, "50%", which ended before the
    voice did; the line was cut at that token's end plus a short pad and lost "-to". A line must not end while the
    voice is still above the take's noise floor."""

    def test_line_end_waits_for_silence(self):
        mod = load()
        rms = [0.001] * 400  # 4 s of 10 ms steps at the noise floor
        rms[100:220] = [0.1] * 120  # speech from 1.0 s to 2.2 s
        self.assertTrue(hasattr(mod, "voice_end"), "ingest-voice.py finds where the voice falls silent")
        self.assertAlmostEqual(mod.voice_end(rms, 1.8, 4.0), 2.2, delta=0.02)
        self.assertAlmostEqual(mod.voice_end(rms, 2.3, 4.0), 2.3, delta=0.02, msg="already silent: no extension")
        self.assertLessEqual(mod.voice_end(rms, 1.8, 2.0), 2.0, "never past the next line's cut")


if __name__ == "__main__":
    # report on stdout: Windows PowerShell 5.1 turns native stderr into an error record under $ErrorActionPreference Stop
    unittest.main(testRunner=unittest.TextTestRunner(stream=sys.stdout))
