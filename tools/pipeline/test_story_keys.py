# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Test story_keys na sztucznym repozytorium: przesunięcie okrzyku i efektu, zmiana tekstu, brak źródła.
Uruchamiany z run_tests.sh: python3 tools/pipeline/test_story_keys.py"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import story_keys  # noqa: E402


def write(p, d):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(d, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


class StoryKeysTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        r = self.root = Path(self.tmp.name)
        write(r / "data/barks.json", {"hask": [{"text": "Raz."}, {"text": "Dwa."}]})
        write(r / "data/dialogues/d.json", {"nodes": {"n": {"text": "Tekst.", "effects": [
            {"set_flag": "x"}, {"journal": "Wpis."}]}}})
        write(r / "i18n/en/data.json", {"barks:hask/0/text": "One.", "barks:hask/1/text": "Two.",
                                        "dialogues/d:nodes/n/text": "Text.",
                                        "dialogues/d:nodes/n/effects/1/journal": "Entry."})
        story_keys.init_sources("en", r)
        vd = r / "assets/audio/voice/en/barks"
        vd.mkdir(parents=True)
        for i, t in enumerate(["One.", "Two."]):
            (vd / f"hask_{i}_0.ogg").write_bytes(b"ogg%d" % i)
        write(r / "assets/audio/voice/en/manifest.json", {
            f"barks/hask_{i}": {"segments": [{"who": "speaker", "text": t, "file": f"hask_{i}_0.ogg"}]}
            for i, t in enumerate(["One.", "Two."])})

    def tearDown(self):
        self.tmp.cleanup()

    def test_clean_state(self):
        self.assertEqual(story_keys.run(["en"], root=self.root), [])

    def test_insert_in_middle_is_detected_and_fixed(self):
        r = self.root
        write(r / "data/barks.json", {"hask": [{"text": "Nowy."}, {"text": "Raz."}, {"text": "Dwa."}]})
        write(r / "data/dialogues/d.json", {"nodes": {"n": {"text": "Tekst.", "effects": [
            {"set_flag": "x"}, {"set_flag": "y"}, {"journal": "Wpis."}]}}})
        states = {(k, s) for _, _, s, k, _ in story_keys.run(["en"], root=r)}
        self.assertIn(("barks:hask/0/text", "przesunięty"), states)
        self.assertIn(("dialogues/d:nodes/n/effects/1/journal", "przesunięty"), states)
        story_keys.run(["en"], fix=True, root=r)
        over = json.loads((r / "i18n/en/data.json").read_text())
        self.assertEqual(over["barks:hask/1/text"], "One.")
        self.assertEqual(over["barks:hask/2/text"], "Two.")
        self.assertEqual(over["dialogues/d:nodes/n/effects/2/journal"], "Entry.")
        self.assertNotIn("barks:hask/0/text", over, "nowy okrzyk czeka na tłumaczenie")
        man = json.loads((r / "assets/audio/voice/en/manifest.json").read_text())
        self.assertEqual(man["barks/hask_1"]["segments"][0]["file"], "hask_1_0.ogg")
        self.assertEqual((r / "assets/audio/voice/en/barks/hask_1_0.ogg").read_bytes(), b"ogg0", "plik idzie za tekstem")
        self.assertEqual(story_keys.run(["en"], root=r), [], "po naprawie czysto")

    def test_changed_text_is_stale_not_renamed(self):
        r = self.root
        write(r / "data/barks.json", {"hask": [{"text": "Raz, poprawione."}, {"text": "Dwa."}]})
        rows = story_keys.run(["en"], fix=True, root=r)
        self.assertIn(("nieaktualny", "barks:hask/0/text"), {(s, k) for _, kind, s, k, _ in rows if kind == "tłumaczenie"})
        self.assertEqual([s for _, _, s, k, _ in story_keys.run(["en"], root=r) if k == "barks:hask/0/text"],
                         ["nieaktualny"], "zostaje do ręcznej poprawki")

    def test_new_translation_without_source(self):
        r = self.root
        over = json.loads((r / "i18n/en/data.json").read_text())
        over["dialogues/d:nodes/n/effects/1/journal"] = "Entry!"
        write(r / "i18n/en/data.json", over)
        src = json.loads((r / "i18n/en/data.source.json").read_text())
        del src["dialogues/d:nodes/n/effects/1/journal"]
        write(r / "i18n/en/data.source.json", src)
        rows = story_keys.run(["en"], fix=True, root=r)
        self.assertEqual([s for _, _, s, _, _ in rows], ["bez źródła"])
        self.assertEqual(story_keys.run(["en"], root=r), [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
