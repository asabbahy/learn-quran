"""One live recitation session: audio in, word statuses and stop-on-error out.

The session is recogniser-agnostic: it is fed hypothesis text (re-decoded from
the growing audio buffer) and turns it into events for the app.

Events sent to the client:
  {"type": "progress", "cursor": int, "words": [{"i", "s"}...]}   statuses changed
  {"type": "error", "index", "kind", "heard", "replay": {"scope", "start", "end"}}
  {"type": "segment_done"}                                         all words correct

Stop-on-error rule: an error is only reported once it is *confirmed*: either
the reciter has moved past it (a later word was recognised) or the same error
showed up in two consecutive decodes. That keeps a half-spoken word from
being flagged mid-breath.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from . import arabic
from .align import Status, WordResult, align

ERROR_STATUSES = {Status.HARAKAT, Status.LETTER, Status.WRONG, Status.MISSED}

# Rules whose correct pronunciation spans the boundary into the next word, so
# the model recitation must replay the phrase, not the single word.
CROSS_WORD_RULES = {
    "idgham_ghunnah", "idgham_wo_ghunnah", "idgham_shafawi", "idgham_mutajanisayn",
    "idgham_mutaqaribayn", "ikhafa", "ikhafa_shafawi", "iqlab",
}

SUPPORTED_RIWAYAT = {"hafs"}  # grows as reference models/audio per riwaya are added


@dataclass
class ExpectedWord:
    loc: str                       # "surah:ayah:word"
    text: str                      # Uthmani text with harakat
    end_rules: list[str] = field(default_factory=list)  # tajweed rules on the last letters
    waqf_after: str | None = None  # waqf mark after this word, if any (e.g. "ۚ", "ۖ", "ۗ")
    ayah_end: bool = False


@dataclass
class Replay:
    scope: str  # "word" | "phrase" | "segment"
    start: int
    end: int    # inclusive

    def as_dict(self) -> dict:
        return {"scope": self.scope, "start": self.start, "end": self.end}


def replay_for(words: list[ExpectedWord], index: int, kind: Status) -> Replay:
    """Pick how much model recitation to play for a mistake at `index`.

    * letter / harakat error            -> the word
    * word ends in a cross-word rule,
      or the previous one did           -> the phrase (the pair of words)
    * skipped or wrong word             -> the segment back to the last pause mark
    Waqf/ibtida' errors also map to "segment"; they are raised by the
    segmenter integration (see recognizer.py), not by the word aligner.
    """
    if kind in (Status.MISSED, Status.WRONG):
        start = index
        while start > 0 and not (words[start - 1].waqf_after or words[start - 1].ayah_end):
            start -= 1
        end = index
        while end < len(words) - 1 and not (words[end].waqf_after or words[end].ayah_end):
            end += 1
        return Replay("segment", start, end)
    if any(r in CROSS_WORD_RULES for r in words[index].end_rules) and index + 1 < len(words):
        return Replay("phrase", index, index + 1)
    if index > 0 and any(r in CROSS_WORD_RULES for r in words[index - 1].end_rules):
        return Replay("phrase", index - 1, index)
    return Replay("word", index, index)


class RecitationSession:
    def __init__(self, words: list[ExpectedWord], riwaya: str = "hafs", repeats: int = 2):
        if riwaya not in SUPPORTED_RIWAYAT:
            raise ValueError(f"riwaya '{riwaya}' is not supported by the checker yet")
        self.words = words
        self.riwaya = riwaya
        self.repeats = repeats
        self.start = 0            # first word of the current attempt window
        self.confirmed: list[Status] = [Status.PENDING] * len(words)
        self._last_sent: list[Status] = list(self.confirmed)
        self._pending_error: tuple[int, Status] | None = None
        self.paused_at: int | None = None
        self.retries_left = 0

    # -- feeding hypotheses -------------------------------------------------

    def on_hypothesis(self, text: str, *, final: bool = False) -> list[dict]:
        """Feed the latest full decode of the current attempt's audio."""
        if self.paused_at is not None:
            return []
        expected = [w.text for w in self.words[self.start:]]
        heard = arabic.tokenize(text)
        results, cursor = align(expected, heard, prefix=not final, partial_last=not final)
        results = [WordResult(r.index + self.start, r.status, r.heard) for r in results]
        cursor += self.start

        events: list[dict] = []
        first_err = next((r for r in results if r.status in ERROR_STATUSES), None)

        # Update statuses up to the first error (words after it are unreliable).
        for r in results:
            if first_err and r.index > first_err.index:
                break
            if r.status == Status.CORRECT:
                self.confirmed[r.index] = Status.CORRECT

        if first_err:
            moved_past = cursor > first_err.index + 1
            seen_twice = self._pending_error == (first_err.index, first_err.status)
            if moved_past or seen_twice or final:
                events.extend(self._raise_error(first_err))
            else:
                self._pending_error = (first_err.index, first_err.status)
        else:
            self._pending_error = None

        events = self._progress_event(cursor) + events
        if all(s == Status.CORRECT for s in self.confirmed):
            events.append({"type": "segment_done"})
        return events

    def _raise_error(self, r: WordResult) -> list[dict]:
        self.confirmed[r.index] = r.status
        self.paused_at = r.index
        self._pending_error = None
        replay = replay_for(self.words, r.index, r.status)
        self.retries_left = self.repeats
        self._replay = replay
        return [{
            "type": "error",
            "index": r.index,
            "loc": self.words[r.index].loc,
            "kind": r.status.value,
            "heard": r.heard,
            "replay": replay.as_dict(),
            "repeats": self.repeats,
        }]

    def _progress_event(self, cursor: int) -> list[dict]:
        changed = [{"i": i, "s": s.value} for i, s in enumerate(self.confirmed)
                   if s != self._last_sent[i]]
        self._last_sent = list(self.confirmed)
        return [{"type": "progress", "cursor": cursor, "words": changed}] if changed else []

    # -- correction loop ----------------------------------------------------

    def begin_retry(self) -> dict:
        """Client finished playing the model recitation; user now repeats.

        The next audio is checked against the replay window only.
        """
        assert self.paused_at is not None, "no error to retry"
        rp = self._replay
        self.start = rp.start
        for i in range(rp.start, len(self.words)):
            self.confirmed[i] = Status.PENDING
        self.paused_at = None
        self._window_end = rp.end
        return {"type": "retry_started", "start": rp.start, "end": rp.end,
                "attempts_left": self.retries_left}

    def check_retry(self, text: str) -> list[dict]:
        """Judge one complete repetition of the replay window."""
        end = self._window_end
        expected = [w.text for w in self.words[self.start:end + 1]]
        results, _ = align(expected, arabic.tokenize(text), prefix=False)
        ok = all(r.status == Status.CORRECT for r in results)
        self.retries_left -= 1 if ok else 0
        events: list[dict] = [{
            "type": "retry_result",
            "ok": ok,
            "words": [{"i": r.index + self.start, "s": r.status.value} for r in results],
            "correct_repeats_left": self.retries_left,
        }]
        if ok and self.retries_left <= 0:
            for i in range(self.start, end + 1):
                self.confirmed[i] = Status.CORRECT
            self._last_sent = list(self.confirmed)
            self.start = end + 1
            events.append({"type": "resume", "from": self.start})
            if self.start >= len(self.words):
                events.append({"type": "segment_done"})
        return events
