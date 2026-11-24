"""Arabic text normalisation for comparing recited words with the mushaf text.

Two views of every word are compared:

* skeleton - letters only (rasm), with hamza/alif variants folded. Used to decide
  whether the reciter said the right word at all.
* vowelled - letters plus harakat (fatha, damma, kasra, sukun, shadda, tanwin).
  Used to catch harakat mistakes when the recogniser outputs diacritics.

Uthmani-only marks (small high letters, waqf signs, etc.) are dropped from both,
because recognisers trained on plain text never produce them.
"""
from __future__ import annotations

import re
import unicodedata

# Harakat we keep in the vowelled view.
HARAKAT = set("ًٌٍَُِّْ")  # tanwin x3, fatha, damma, kasra, shadda, sukun

# Quranic annotation marks: small letters, waqf signs, rounded zero, madd, etc.
_QURANIC_MARKS = re.compile(
    "[ؐ-ؚٓ-ٰٟۖ-ۭ࣓-ࣿـ]"
)

_FOLD = str.maketrans({
    "ٱ": "ا",  # alif wasla -> alif
    "آ": "ا",  # alif madda -> alif
    "أ": "ا",  # hamza above -> alif
    "إ": "ا",  # hamza below -> alif
    "ى": "ي",  # alif maqsura -> ya
    "ی": "ي",  # farsi ya -> ya
    "ة": "ه",  # ta marbuta -> ha (recognisers vary)
    "ؤ": "ء",  # hamza on waw -> hamza
    "ئ": "ء",  # hamza on ya -> hamza
})

_NON_ARABIC = re.compile(r"[^ء-يً-ْ\s]")


def _base(text: str) -> str:
    text = unicodedata.normalize("NFC", text)
    text = _QURANIC_MARKS.sub("", text)
    text = text.translate(_FOLD)
    return _NON_ARABIC.sub("", text)


def skeleton(word: str) -> str:
    return "".join(ch for ch in _base(word) if ch not in HARAKAT and not ch.isspace())


def vowelled(word: str) -> str:
    return "".join(ch for ch in _base(word) if not ch.isspace())


def has_harakat(text: str) -> bool:
    return any(ch in HARAKAT for ch in text)


def tokenize(text: str) -> list[str]:
    return [t for t in _base(text).split() if skeleton(t)]


def char_similarity(a: str, b: str) -> float:
    """1.0 for identical skeletons, falling towards 0 with edit distance."""
    if a == b:
        return 1.0
    if not a or not b:
        return 0.0
    d = levenshtein(a, b)
    return max(0.0, 1.0 - d / max(len(a), len(b)))


def levenshtein(a: str, b: str) -> int:
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]
