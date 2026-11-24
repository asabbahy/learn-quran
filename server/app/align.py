"""Align what the recogniser heard against the expected words.

The alignment is a Needleman-Wunsch style DP over words, where substituting one
word for another costs (1 - skeleton similarity). It runs in *prefix* mode: the
reciter is usually part-way through the passage, so unrecited words at the end
cost nothing and are reported as "pending", not "missed".
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from . import arabic


class Status(str, Enum):
    PENDING = "pending"   # not reached yet
    CORRECT = "correct"
    HARAKAT = "harakat"   # right letters, wrong vowels
    LETTER = "letter"     # close, but a letter is wrong
    WRONG = "wrong"       # a different word
    MISSED = "missed"     # skipped while later words were recited


@dataclass
class WordResult:
    index: int
    status: Status
    heard: str | None = None


GAP = 1.0             # cost of a skipped or extra word
LETTER_THRESHOLD = 0.6  # similarity above this = same word with a letter error


def _sub_cost(sim: float) -> float:
    # Close words (a letter off) are cheap substitutions. A different word costs
    # more than one GAP, so "skip a word, then say the next one right" aligns as
    # MISSED + CORRECT, but stays below delete+insert (2 * GAP), so a plain
    # wrong word shows as WRONG rather than MISSED plus an extra word.
    if sim >= LETTER_THRESHOLD:
        return 1.0 - sim
    return GAP + 0.5 * (1.0 - sim)


def align(expected: list[str], heard: list[str], *, prefix: bool = True,
          partial_last: bool = False) -> tuple[list[WordResult], int]:
    """Return per-expected-word results and the cursor (index of the next word).

    expected     - mushaf words for the passage (Uthmani, with harakat)
    heard        - recogniser tokens
    prefix       - unrecited trailing words are free (streaming)
    partial_last - the last heard token may be a word still being spoken
    """
    n, m = len(expected), len(heard)
    exp_sk = [arabic.skeleton(w) for w in expected]
    hyp_sk = [arabic.skeleton(w) for w in heard]

    INF = float("inf")
    cost = [[INF] * (m + 1) for _ in range(n + 1)]
    back: list[list[str | None]] = [[None] * (m + 1) for _ in range(n + 1)]
    cost[0][0] = 0.0
    for i in range(n + 1):
        for j in range(m + 1):
            c = cost[i][j]
            if c == INF:
                continue
            if i < n and j < m:
                sim = arabic.char_similarity(exp_sk[i], hyp_sk[j])
                nc = c + _sub_cost(sim)
                if nc < cost[i + 1][j + 1]:
                    cost[i + 1][j + 1], back[i + 1][j + 1] = nc, "sub"
            if i < n:
                nc = c + GAP
                if nc < cost[i + 1][j]:
                    cost[i + 1][j], back[i + 1][j] = nc, "del"
            if j < m:
                nc = c + GAP
                if nc < cost[i][j + 1]:
                    cost[i][j + 1], back[i][j + 1] = nc, "ins"

    # Where does the alignment end? Full mode: (n, m). Prefix mode: any i with all
    # heard tokens consumed; prefer the cheapest, then the furthest along.
    if prefix:
        end_i = min(range(n + 1), key=lambda i: (round(cost[i][m], 6), -i))
    else:
        end_i = n

    results = [WordResult(i, Status.PENDING) for i in range(n)]
    i, j = end_i, m
    pairs: list[tuple[int, int | None]] = []
    while i > 0 or j > 0:
        op = back[i][j]
        if op == "sub":
            pairs.append((i - 1, j - 1)); i -= 1; j -= 1
        elif op == "del":
            pairs.append((i - 1, None)); i -= 1
        else:  # "ins" (extra word heard) - nothing to record against expected
            j -= 1
    pairs.reverse()

    for ei, hj in pairs:
        if hj is None:
            results[ei] = WordResult(ei, Status.MISSED)
            continue
        h = heard[hj]
        sim = arabic.char_similarity(exp_sk[ei], hyp_sk[hj])
        is_last = hj == m - 1
        if sim >= 0.999:
            status = Status.CORRECT
            if arabic.has_harakat(h) and arabic.vowelled(h) != arabic.vowelled(expected[ei]):
                status = Status.HARAKAT
        elif partial_last and is_last and exp_sk[ei].startswith(hyp_sk[hj]):
            status = Status.PENDING  # still being spoken
        elif sim >= LETTER_THRESHOLD:
            status = Status.LETTER
        else:
            status = Status.WRONG
        results[ei] = WordResult(ei, status, heard=h)

    # A trailing MISSED run in prefix mode just means "not reached yet".
    k = end_i - 1
    while prefix and k >= 0 and results[k].status == Status.MISSED:
        results[k] = WordResult(k, Status.PENDING)
        k -= 1
    cursor = k + 1
    while cursor > 0 and results[cursor - 1].status == Status.PENDING:
        cursor -= 1
    return results, cursor
