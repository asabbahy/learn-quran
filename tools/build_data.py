#!/usr/bin/env python3
"""Build the app's bundled Quran data from verified sources.

Nothing in this repo contains hand-typed Quranic text. Every word the app shows
comes from this script, which pulls it from:

  * Quran.com API v4  - Uthmani text (Hafs), word list, word audio paths, and
                        colour-coded tajweed markup.
  * Quranic Arabic Corpus morphology v0.4 (optional) - root, lemma and grammar
    for each word segment. The corpus licence requires you to download the file
    yourself from https://corpus.quran.com/download/ (GNU GPL, attribution
    required). Pass it with --morphology.

Output: app/assets/quran/surah_<n>.json, one file per surah, plus index.json.

Usage:
    python tools/build_data.py                      # the default short-surah set
    python tools/build_data.py --surahs 1 112-114   # specific surahs
    python tools/build_data.py --all --morphology quranic-corpus-morphology-0.4.txt

Standard library only, so it runs anywhere Python 3.9+ is installed.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

API = "https://api.quran.com/api/v4"
ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "app" / "assets" / "quran"

# Al-Fatiha plus Juz' 'Amma's short surahs: what the learning path starts with.
DEFAULT_SURAHS = [1] + list(range(93, 115))


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

def get_json(url: str, retries: int = 3) -> dict:
    last: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "learn-quran-data/0.1"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as exc:  # network hiccups: back off and retry
            last = exc
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"GET {url} failed: {last}")


# ---------------------------------------------------------------------------
# Tajweed markup -> per-word segments
# ---------------------------------------------------------------------------

class _TajweedParser(HTMLParser):
    """Turns Quran.com's text_uthmani_tajweed HTML into (char, rule) pairs.

    The markup looks like: <tajweed class=ham_wasl>ٱ</tajweed>لْحَمْدُ ...
    <span class=end>٢</span>. Verse-end number spans are dropped.
    """

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str | None] = []
        self.skip = 0
        self.chars: list[tuple[str, str | None]] = []

    def handle_starttag(self, tag, attrs):
        cls = dict(attrs).get("class")
        if tag == "span" and cls == "end":
            self.skip += 1
        self.stack.append(cls if tag == "tajweed" else None)

    def handle_endtag(self, tag):
        if self.stack:
            cls = self.stack.pop()
            if tag == "span" and self.skip and cls is None:
                self.skip = max(0, self.skip - 1)

    def handle_data(self, data):
        if self.skip:
            return
        rule = next((c for c in reversed(self.stack) if c), None)
        for ch in data:
            self.chars.append((ch, rule))


def tajweed_words(html: str) -> list[list[dict]]:
    """Split tajweed HTML into words; each word is a list of {t, r} segments."""
    p = _TajweedParser()
    p.feed(html)
    words: list[list[dict]] = []
    current: list[dict] = []
    for ch, rule in p.chars:
        if ch.isspace():
            if current:
                words.append(current)
                current = []
            continue
        if current and current[-1].get("r") == rule:
            current[-1]["t"] += ch
        else:
            seg = {"t": ch}
            if rule:
                seg["r"] = rule
            current.append(seg)
    if current:
        words.append(current)
    # Strip a trailing verse number if it slipped through as plain digits.
    if words and all(re.fullmatch(r"[٠-٩]+", s["t"]) for s in words[-1]):
        words.pop()
    return words


# ---------------------------------------------------------------------------
# Quranic Arabic Corpus morphology (optional)
# ---------------------------------------------------------------------------

# Buckwalter -> Arabic, as used by the corpus file.
_BW = {
    "'": "ء", ">": "أ", "&": "ؤ", "<": "إ", "}": "ئ", "A": "ا", "b": "ب", "p": "ة",
    "t": "ت", "v": "ث", "j": "ج", "H": "ح", "x": "خ", "d": "د", "*": "ذ", "r": "ر",
    "z": "ز", "s": "س", "$": "ش", "S": "ص", "D": "ض", "T": "ط", "Z": "ظ", "E": "ع",
    "g": "غ", "_": "ـ", "f": "ف", "q": "ق", "k": "ك", "l": "ل", "m": "م", "n": "ن",
    "h": "ه", "w": "و", "Y": "ى", "y": "ي", "F": "ً", "N": "ٌ", "K": "ٍ", "a": "َ",
    "u": "ُ", "i": "ِ", "~": "ّ", "o": "ْ", "`": "ٰ", "{": "ٱ", "^": "ٓ", "#": "ٔ",
    "@": "۟", "[": "ۢ", ";": "۠", ",": "ۭ", ".": "ۜ", "!": "ۨ", "-": "ۣ", "+": "ۥ",
    "%": "ۦ", "]": "ۭ",
}


def bw_to_ar(s: str) -> str:
    return "".join(_BW.get(c, c) for c in s)


POS_NAMES = {
    "N": "noun", "PN": "proper noun", "V": "verb", "ADJ": "adjective", "PRON": "pronoun",
    "DEM": "demonstrative", "REL": "relative pronoun", "P": "preposition",
    "CONJ": "conjunction", "DET": "determiner", "NEG": "negative particle",
    "T": "time adverb", "LOC": "location adverb", "INL": "Quranic initials",
    "VOC": "vocative particle", "EMPH": "emphatic particle", "INTG": "interrogative",
    "COND": "conditional", "SUB": "subordinating conjunction", "ACC": "accusative particle",
    "RES": "restriction particle", "PRO": "prohibition particle", "FUT": "future particle",
    "CERT": "particle of certainty", "AMD": "amendment particle", "ANS": "answer particle",
    "AVR": "aversion particle", "CAUS": "particle of cause", "CIRC": "circumstantial particle",
    "COM": "comitative particle", "EQ": "equalization particle", "EXH": "exhortation particle",
    "EXL": "explanation particle", "EXP": "exceptive particle", "IMPN": "imperative verbal noun",
    "IMPV": "imperative particle", "INC": "inceptive particle", "INT": "particle of interpretation",
    "PREV": "preventive particle", "PRP": "purpose particle", "REM": "resumption particle",
    "RET": "retraction particle", "RSLT": "result particle", "SUP": "supplemental particle",
    "SUR": "surprise particle",
}


def load_morphology(path: Path) -> dict[str, list[dict]]:
    """Return {"s:a:w": [segment, ...]} from the corpus v0.4 text file."""
    out: dict[str, list[dict]] = {}
    line_re = re.compile(r"^\((\d+):(\d+):(\d+):(\d+)\)\t([^\t]*)\t([^\t]*)\t(.*)$")
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            m = line_re.match(line.rstrip("\n"))
            if not m:
                continue  # header / comments
            s, a, w, _seg, form, tag, feats = m.groups()
            seg: dict = {"form": bw_to_ar(form), "pos": tag, "pos_name": POS_NAMES.get(tag, tag)}
            for f in feats.split("|"):
                if f.startswith("ROOT:"):
                    seg["root"] = " ".join(bw_to_ar(f[5:]))
                elif f.startswith("LEM:"):
                    seg["lemma"] = bw_to_ar(f[4:])
                elif f in ("PREFIX", "STEM", "SUFFIX"):
                    seg["kind"] = f.lower()
            seg["features"] = feats
            out.setdefault(f"{s}:{a}:{w}", []).append(seg)
    return out


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def fetch_surah(n: int) -> list[dict]:
    verses: list[dict] = []
    page = 1
    while True:
        url = (f"{API}/verses/by_chapter/{n}?words=true&per_page=50&page={page}"
               "&fields=text_uthmani,text_uthmani_tajweed"
               "&word_fields=text_uthmani,location,audio_url")
        data = get_json(url)
        verses.extend(data["verses"])
        nxt = (data.get("pagination") or {}).get("next_page")
        if not nxt:
            return verses
        page = nxt


def build_surah(n: int, info: dict, morph: dict[str, list[dict]] | None) -> dict:
    verses_out = []
    root_index: dict[str, list[str]] = {}
    for v in fetch_surah(n):
        words = [w for w in v["words"] if w.get("char_type_name") == "word"]
        tj = tajweed_words(v.get("text_uthmani_tajweed") or "")
        tj_ok = len(tj) == len(words)
        if not tj_ok:
            print(f"  ! {v['verse_key']}: tajweed split {len(tj)} != {len(words)} words; "
                  "showing plain text for this verse", file=sys.stderr)
        out_words = []
        for i, w in enumerate(words):
            loc = w["location"]  # "s:a:w"
            item = {
                "loc": loc,
                "text": w["text_uthmani"],
                "tajweed": tj[i] if tj_ok else [{"t": w["text_uthmani"]}],
            }
            if w.get("audio_url"):
                item["audio"] = w["audio_url"]
            if morph is not None and loc in morph:
                segs = morph[loc]
                item["morph"] = segs
                root = next((s["root"] for s in segs if "root" in s), None)
                if root:
                    item["root"] = root
                    root_index.setdefault(root, []).append(loc)
            out_words.append(item)
        verses_out.append({
            "key": v["verse_key"],
            "number": v["verse_number"],
            "text": v["text_uthmani"],
            "words": out_words,
        })
    return {
        "number": n,
        "name_arabic": info["name_arabic"],
        "name_simple": info["name_simple"],
        "translated_name": (info.get("translated_name") or {}).get("name"),
        "revelation_place": info.get("revelation_place"),
        "verses_count": info["verses_count"],
        "riwaya": "hafs",
        "source": "Quran.com API v4 (Uthmani, Hafs 'an 'Asim)"
                  + ("; morphology: Quranic Arabic Corpus v0.4" if morph else ""),
        "verses": verses_out,
        "roots_in_surah": root_index,
    }


def parse_surahs(tokens: list[str]) -> list[int]:
    out: list[int] = []
    for t in tokens:
        if "-" in t:
            a, b = (int(x) for x in t.split("-"))
            out.extend(range(min(a, b), max(a, b) + 1))
        else:
            out.append(int(t))
    bad = [s for s in out if not 1 <= s <= 114]
    if bad:
        raise SystemExit(f"Surah numbers must be 1-114: {bad}")
    return sorted(set(out))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--surahs", nargs="*", help="e.g. 1 112-114")
    ap.add_argument("--all", action="store_true", help="all 114 surahs")
    ap.add_argument("--morphology", type=Path, help="path to quranic-corpus-morphology-0.4.txt")
    ap.add_argument("--out", type=Path, default=OUT_DIR)
    args = ap.parse_args()

    surahs = list(range(1, 115)) if args.all else parse_surahs(args.surahs) if args.surahs else DEFAULT_SURAHS
    morph = load_morphology(args.morphology) if args.morphology else None
    if morph is None:
        print("note: no --morphology file given; word roots/grammar will be empty.", file=sys.stderr)

    chapters = {c["id"]: c for c in get_json(f"{API}/chapters")["chapters"]}
    args.out.mkdir(parents=True, exist_ok=True)

    index = []
    for n in surahs:
        print(f"surah {n} ...")
        data = build_surah(n, chapters[n], morph)
        (args.out / f"surah_{n}.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        index.append({k: data[k] for k in ("number", "name_arabic", "name_simple",
                                           "translated_name", "verses_count", "revelation_place")})
    (args.out / "index.json").write_text(
        json.dumps({"riwaya": "hafs", "surahs": index}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {len(index)} surahs to {args.out}")


if __name__ == "__main__":
    main()
