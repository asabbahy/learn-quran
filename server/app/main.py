"""Recitation-check server.

Run:  uvicorn app.main:app --host 0.0.0.0 --port 8000
      RECOGNIZER=whisper uvicorn app.main:app ...   (real model)

WebSocket /ws/recite protocol
-----------------------------
client -> server (JSON text frames)
  {"type": "start", "riwaya": "hafs", "repeats": 2,
   "words": [{"loc": "1:1:1", "text": "...", "end_rules": [], "waqf_after": null, "ayah_end": false}, ...]}
  {"type": "replay_done"}      model recitation finished playing; user will repeat
  {"type": "attempt_end"}      user finished one repetition (retry mode)
  {"type": "stop"}             user stopped; do a final decode
  {"type": "debug_hypothesis", "text": "...", "final": false}   mock recogniser only

client -> server (binary frames)
  16 kHz, mono, signed 16-bit little-endian PCM

server -> client: see app/session.py for event shapes, plus
  {"type": "ready", "recognizer": "mock"|"whisper"}
  {"type": "fatal", "message": "..."}
"""
from __future__ import annotations

import asyncio
import json
from array import array

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from .recognizer import make_recognizer
from .session import ExpectedWord, RecitationSession

SAMPLE_RATE = 16000
DECODE_EVERY_S = 0.8     # re-decode the live buffer this often
MAX_BUFFER_S = 20.0      # Whisper's window is 30 s; rebase before we get close

app = FastAPI(title="Learn Quran - recitation checker")
recognizer = make_recognizer()


@app.get("/health")
def health() -> dict:
    return {"ok": True, "recognizer": recognizer.name}


def _pcm16_to_float(buf: bytearray):
    samples = array("h")
    samples.frombytes(bytes(buf[: len(buf) // 2 * 2]))
    try:
        import numpy as np
        return np.asarray(samples, dtype=np.float32) / 32768.0
    except ImportError:  # mock mode without numpy
        return [s / 32768.0 for s in samples]


@app.websocket("/ws/recite")
async def recite(ws: WebSocket) -> None:
    await ws.accept()
    session: RecitationSession | None = None
    audio = bytearray()
    decoded_bytes = 0
    mode = "live"  # "live" | "paused" | "retry"
    decode_lock = asyncio.Lock()

    async def send_all(events: list[dict]) -> None:
        nonlocal mode, audio, decoded_bytes
        for ev in events:
            if ev["type"] == "error":
                mode = "paused"
            elif ev["type"] == "resume":
                mode = "live"
                audio, decoded_bytes = bytearray(), 0
            await ws.send_text(json.dumps(ev, ensure_ascii=False))

    async def transcribe_buffer() -> str:
        data = _pcm16_to_float(audio)
        return await asyncio.to_thread(recognizer.transcribe, data)

    await ws.send_text(json.dumps({"type": "ready", "recognizer": recognizer.name}))
    try:
        while True:
            msg = await ws.receive()
            if msg.get("type") == "websocket.disconnect":
                break

            if msg.get("bytes") is not None:
                if session is None or mode == "paused":
                    continue
                audio.extend(msg["bytes"])
                new_s = (len(audio) - decoded_bytes) / 2 / SAMPLE_RATE
                if mode == "live" and new_s >= DECODE_EVERY_S and not decode_lock.locked():
                    async with decode_lock:
                        decoded_bytes = len(audio)
                        events = session.on_hypothesis(await transcribe_buffer())
                        await send_all(events)
                        # Keep the buffer inside Whisper's window: once everything so
                        # far is confirmed correct, start a fresh buffer at the cursor.
                        if mode == "live" and len(audio) / 2 / SAMPLE_RATE > MAX_BUFFER_S:
                            cursor = next((i for i, s in enumerate(session.confirmed)
                                           if s.value != "correct"), len(session.words))
                            session.start = cursor
                            audio, decoded_bytes = bytearray(), 0
                continue

            data = json.loads(msg.get("text") or "{}")
            kind = data.get("type")

            if kind == "start":
                try:
                    words = [ExpectedWord(
                        loc=w["loc"], text=w["text"],
                        end_rules=w.get("end_rules") or [],
                        waqf_after=w.get("waqf_after"),
                        ayah_end=bool(w.get("ayah_end")),
                    ) for w in data["words"]]
                    session = RecitationSession(words, data.get("riwaya", "hafs"),
                                                int(data.get("repeats", 2)))
                except (KeyError, ValueError) as exc:
                    await ws.send_text(json.dumps({"type": "fatal", "message": str(exc)}))
                    continue
                audio, decoded_bytes, mode = bytearray(), 0, "live"

            elif session is None:
                await ws.send_text(json.dumps({"type": "fatal", "message": "send 'start' first"}))

            elif kind == "replay_done" and mode == "paused":
                audio, decoded_bytes = bytearray(), 0
                mode = "retry"
                await send_all([session.begin_retry()])

            elif kind == "attempt_end" and mode == "retry":
                text = await transcribe_buffer()
                audio, decoded_bytes = bytearray(), 0
                await send_all(session.check_retry(text))

            elif kind == "stop" and mode == "live":
                async with decode_lock:
                    await send_all(session.on_hypothesis(await transcribe_buffer(), final=True))

            elif kind == "debug_hypothesis":
                text, final = data.get("text", ""), bool(data.get("final"))
                if mode == "retry":
                    await send_all(session.check_retry(text))
                elif mode == "live":
                    await send_all(session.on_hypothesis(text, final=final))

    except WebSocketDisconnect:
        pass
