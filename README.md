# Learn Quran

An app for kids and adults that teaches you to recite the Quran properly and to understand it through its language. Learning is Duolingo-style, understanding is language-first, and interpretation is optional and neutral.

```
app/      Flutter app: learning path, reader with tajweed colours, word tap, live recitation check
server/   Recitation-check server (FastAPI + WebSocket): Whisper Quran model, word alignment, correction loop
tools/    build_data.py: builds the app's Quran data from verified sources
```

## What works in this first cut

| Area | Status |
|---|---|
| Learning path (streak, XP, unlock order: Al-Fatiha, then An-Nas upwards) | ✅ |
| Reader: Uthmani text, full tashkil, colour-coded tajweed, colour key | ✅ |
| Word tap: root, morphology, tajweed in the word, same root in the surah | ✅ (needs the corpus file, see below) |
| Live check: words go green/red, stop on error, model recitation, repeat N times, carry on | ✅ loop; needs the Whisper model for real audio |
| Replay fits the mistake: word / phrase (cross-word tajweed) / segment (skip or wrong word) | ✅ |
| Riwaya picker; checker refuses readings it can't judge yet | ✅ Hafs only so far |
| Pace (tahqiq / tadwir / hadr) for model recitation | ✅ (reciter folders need verifying) |
| Lexicon meanings, asbab al-nuzul, haqiqa/majaz, tafsir, themes | ⏳ next |
| Phoneme-level tajweed scoring (madd, ghunna, qalqala), waqf checks | ⏳ next |

No Quranic text is typed by hand anywhere in this repo. All of it comes from `tools/build_data.py`.

## 1. Build the Quran data

```bash
python3 tools/build_data.py            # Al-Fatiha + surahs 93-114 (default learning set)
python3 tools/build_data.py --all      # all 114
```

For roots and grammar on word tap, download `quranic-corpus-morphology-0.4.txt` from https://corpus.quran.com/download/ (the licence requires attribution, and you must download it yourself), then:

```bash
python3 tools/build_data.py --morphology path/to/quranic-corpus-morphology-0.4.txt
```

Output goes to `app/assets/quran/`, which is git-ignored, so rebuild it after cloning.

## 2. Run the checker server

```bash
cd server
python3 -m venv .venv && source .venv/bin/activate

# Mock mode: no model. The app shows a text box where you type what you "recited".
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000

# Real model (tarteel-ai/whisper-base-ar-quran). A GPU is strongly recommended.
pip install -r requirements-ml.txt
RECOGNIZER=whisper uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Tests (standard library only): `cd server && python3 -m unittest discover -s tests`

## 3. Run the app

The platform folders aren't committed yet. Generate them once:

```bash
cd app
flutter create . --platforms=android,ios --project-name learn_quran
flutter pub get
```

Then add microphone permission:

- **Android** `android/app/src/main/AndroidManifest.xml`: `<uses-permission android:name="android.permission.RECORD_AUDIO"/>` and `<uses-permission android:name="android.permission.INTERNET"/>`
- **iOS** `ios/Runner/Info.plist`: `NSMicrophoneUsageDescription` = "To check your recitation"

```bash
flutter run
```

The default server URL is `ws://10.0.2.2:8000/ws/recite`, which is the Android emulator's address for your computer. On a real phone or the iOS simulator, change it in **Settings → Checker server** (e.g. `ws://192.168.1.10:8000/ws/recite`).

Needs Flutter 3.35+.

## Licences to confirm before commercial release

- Whisper Quran checkpoint: check its model card licence
- Quranic Arabic Corpus: GNU GPL, attribution required
- Quran.com text, tajweed markup and word audio: check the API terms
- everyayah.com recitations: check per reciter
- Lexicon and tafsir texts (al-Mufradat, Lisan al-Arab, al-Tabari, Ibn Kathir): to be decided
- Font: currently Amiri Quran (OFL) via google_fonts; the KFGQPC Uthmanic font can replace it
