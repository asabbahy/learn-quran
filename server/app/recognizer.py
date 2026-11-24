"""Speech recognisers behind one tiny interface: 16 kHz mono float32 audio -> text.

Backends (choose with RECOGNIZER env var):

  whisper  - Tarteel's Whisper fine-tuned on Quranic recitation (default model
             "tarteel-ai/whisper-base-ar-quran" on Hugging Face). Needs
             `pip install -r requirements-ml.txt`. GPU strongly recommended.
  mock     - no model. The client sends {"type": "debug_hypothesis", "text": ...}
             instead of audio, so the app's live loop can be built and tested
             without a GPU.

Licence check before commercial use: confirm the licence on the model card of
whichever checkpoint you deploy.

Planned additions (not wired yet):
  * phoneme-level tajweed scorer (ICML 2026 Quran pronunciation-error model /
    Quran Phonetic Script) for madd length, ghunna, qalqala;
  * recitation-segmenter-v2 for waqf / ibtida' checks;
  * one reference model per riwaya, so correct Warsh is never judged as Hafs.
"""
from __future__ import annotations

import os
from typing import Protocol


class Recognizer(Protocol):
    name: str

    def transcribe(self, audio) -> str: ...


class MockRecognizer:
    name = "mock"

    def transcribe(self, audio) -> str:  # audio ignored
        return ""


class WhisperRecognizer:
    name = "whisper"

    def __init__(self, model_id: str | None = None, device: str | None = None):
        import torch  # imported lazily so tests and mock mode need no ML stack
        from transformers import pipeline

        model_id = model_id or os.environ.get("WHISPER_MODEL", "tarteel-ai/whisper-base-ar-quran")
        if device is None:
            device = "cuda:0" if torch.cuda.is_available() else "cpu"
        self._pipe = pipeline(
            "automatic-speech-recognition",
            model=model_id,
            device=device,
            torch_dtype=torch.float16 if device.startswith("cuda") else torch.float32,
        )
        self._gen = {"language": "ar", "task": "transcribe"}

    def transcribe(self, audio) -> str:
        if len(audio) < 1600:  # < 0.1 s
            return ""
        out = self._pipe({"raw": audio, "sampling_rate": 16000}, generate_kwargs=self._gen)
        return out["text"].strip()


def make_recognizer() -> Recognizer:
    kind = os.environ.get("RECOGNIZER", "mock").lower()
    if kind == "whisper":
        return WhisperRecognizer()
    if kind == "mock":
        return MockRecognizer()
    raise ValueError(f"unknown RECOGNIZER={kind}")
