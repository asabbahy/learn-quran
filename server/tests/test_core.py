"""Tests for alignment and the correction loop. Standard library only:
    cd server && python -m unittest discover -s tests

Test words are everyday Arabic, not Quranic text.
"""
import unittest

from app import arabic
from app.align import Status, align
from app.session import ExpectedWord, RecitationSession, replay_for

W = ["ذَهَبَ", "ٱلْوَلَدُ", "إِلَى", "ٱلْمَدْرَسَةِ", "صَبَاحًا"]


def words(**overrides):
    out = [ExpectedWord(loc=f"0:0:{i+1}", text=t) for i, t in enumerate(W)]
    for idx, kw in overrides.items():
        for k, v in kw.items():
            setattr(out[int(idx[1:])], k, v)
    return out


class ArabicTests(unittest.TestCase):
    def test_skeleton_folds_alif_variants_and_strips_harakat(self):
        self.assertEqual(arabic.skeleton("ٱلْوَلَدُ"), "الولد")
        self.assertEqual(arabic.skeleton("إِلَى"), "الي")

    def test_vowelled_keeps_harakat(self):
        self.assertTrue(arabic.has_harakat(arabic.vowelled("ذَهَبَ")))


class AlignTests(unittest.TestCase):
    def test_all_correct_plain_text(self):
        res, cur = align(W, "ذهب الولد الى المدرسة صباحا".split(), prefix=False)
        self.assertTrue(all(r.status == Status.CORRECT for r in res))
        self.assertEqual(cur, 5)

    def test_prefix_leaves_rest_pending(self):
        res, cur = align(W, ["ذهب", "الولد"])
        self.assertEqual([r.status for r in res[:2]], [Status.CORRECT] * 2)
        self.assertTrue(all(r.status == Status.PENDING for r in res[2:]))
        self.assertEqual(cur, 2)

    def test_letter_error(self):
        res, _ = align(W, ["ذهب", "الولد", "الى", "المدرصة"])
        self.assertEqual(res[3].status, Status.LETTER)

    def test_harakat_error(self):
        res, _ = align(W, ["ذَهَبَ", "ٱلْوَلَدِ"])
        self.assertEqual(res[1].status, Status.HARAKAT)

    def test_skipped_word(self):
        res, _ = align(W, ["ذهب", "الولد", "المدرسة"])
        self.assertEqual(res[2].status, Status.MISSED)
        self.assertEqual(res[3].status, Status.CORRECT)

    def test_wrong_word(self):
        res, _ = align(W, ["ذهب", "البنت", "الى"])
        self.assertIn(res[1].status, (Status.WRONG, Status.LETTER))
        self.assertEqual(res[2].status, Status.CORRECT)

    def test_partial_last_word_is_pending(self):
        res, cur = align(W, ["ذهب", "الو"], partial_last=True)
        self.assertEqual(res[1].status, Status.PENDING)
        self.assertEqual(cur, 1)


class ReplayTests(unittest.TestCase):
    def test_letter_error_replays_word(self):
        self.assertEqual(replay_for(words(), 2, Status.LETTER).scope, "word")

    def test_cross_word_rule_replays_phrase(self):
        r = replay_for(words(w1={"end_rules": ["ikhafa"]}), 1, Status.HARAKAT)
        self.assertEqual((r.scope, r.start, r.end), ("phrase", 1, 2))

    def test_skip_replays_segment_to_pause(self):
        r = replay_for(words(w1={"waqf_after": "ۚ"}), 3, Status.MISSED)
        self.assertEqual((r.scope, r.start, r.end), ("segment", 2, 4))


class SessionTests(unittest.TestCase):
    def test_error_needs_confirmation_then_pauses(self):
        s = RecitationSession(words(), repeats=2)
        ev = s.on_hypothesis("ذهب المولد")
        self.assertFalse(any(e["type"] == "error" for e in ev))   # first sighting
        ev = s.on_hypothesis("ذهب المولد")
        err = [e for e in ev if e["type"] == "error"]
        self.assertEqual(len(err), 1)
        self.assertEqual(err[0]["index"], 1)
        self.assertEqual(s.on_hypothesis("ذهب الولد الى"), [])   # paused: ignored

    def test_moving_past_error_confirms_it(self):
        s = RecitationSession(words())
        ev = s.on_hypothesis("ذهب المولد الى المدرسة")
        self.assertTrue(any(e["type"] == "error" for e in ev))

    def test_full_correction_loop(self):
        s = RecitationSession(words(), repeats=2)
        s.on_hypothesis("ذهب المولد الى المدرسة")
        start = s.begin_retry()
        self.assertEqual((start["start"], start["end"]), (1, 1))
        ev = s.check_retry("المولد")
        self.assertFalse(ev[0]["ok"])
        ev = s.check_retry("الولد")
        self.assertTrue(ev[0]["ok"])
        self.assertFalse(any(e["type"] == "resume" for e in ev))   # 1 more needed
        ev = s.check_retry("الولد")
        resume = [e for e in ev if e["type"] == "resume"]
        self.assertEqual(resume[0]["from"], 2)
        ev = s.on_hypothesis("الى المدرسة صباحا", final=True)
        self.assertTrue(any(e["type"] == "segment_done" for e in ev))

    def test_unsupported_riwaya_rejected(self):
        with self.assertRaises(ValueError):
            RecitationSession(words(), riwaya="warsh")


if __name__ == "__main__":
    unittest.main()
