import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/progress_store.dart';
import '../recitation/model_audio.dart';
import '../recitation/recite_client.dart';
import '../widgets/quran_text.dart';

enum _Phase { connecting, ready, listening, playingModel, repeating, done, failed }

/// The live correction loop:
///   1. words turn green / red as you recite
///   2. the app stops at a mistake
///   3. plays the expert recitation of the word, phrase or segment
///   4. you repeat it N times (each attempt re-checked)
///   5. carries on once it's right
class ReciteScreen extends StatefulWidget {
  const ReciteScreen({super.key, required this.surah, required this.store});
  final Surah surah;
  final ProgressStore store;

  @override
  State<ReciteScreen> createState() => _ReciteScreenState();
}

class _ReciteScreenState extends State<ReciteScreen> {
  late final List<Word> _words = widget.surah.allWords;
  late final Set<int> _verseEnds = {
    for (var i = 0; i < _words.length; i++)
      if (i == _words.length - 1 || _words[i + 1].ayah != _words[i].ayah) i,
  };

  late final ReciteClient _client = ReciteClient(widget.store.serverUrl);
  final _audio = ModelAudio();
  StreamSubscription<Map<String, dynamic>>? _sub;

  _Phase _phase = _Phase.connecting;
  final _states = <int, WordState>{};
  String? _message;
  bool _mockServer = false;
  Map<String, dynamic>? _replay; // {scope, start, end}
  int _correctLeft = 0;
  final _debugCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final store = widget.store;
    if (!store.riwaya.available) {
      setState(() {
        _phase = _Phase.failed;
        _message = 'Recitation checking for ${store.riwaya.label} is coming. '
            'Switch to Hafs in Settings for now.';
      });
      return;
    }
    try {
      _sub = _client.events.listen(_onEvent);
      await _client.connect(words: _words, riwaya: store.riwaya.name, repeats: store.repeats);
      setState(() => _phase = _Phase.ready);
    } catch (e) {
      setState(() {
        _phase = _Phase.failed;
        _message = 'Could not reach the checker at ${store.serverUrl}. Check the server URL in Settings.';
      });
    }
  }

  Future<void> _startListening() async {
    final ok = await _client.startMic();
    if (!ok) {
      setState(() => _message = 'Microphone permission is needed to check your recitation.');
      return;
    }
    setState(() {
      _phase = _Phase.listening;
      _states[0] = WordState.current;
      _message = 'Begin reciting';
    });
  }

  Future<void> _onEvent(Map<String, dynamic> ev) async {
    switch (ev['type']) {
      case 'ready':
        _mockServer = ev['recognizer'] == 'mock';
      case 'progress':
        for (final w in (ev['words'] as List)) {
          final i = w['i'] as int;
          _states[i] = switch (w['s']) {
            'correct' => WordState.correct,
            'pending' => WordState.idle,
            _ => WordState.error,
          };
        }
        final cursor = ev['cursor'] as int;
        if (cursor < _words.length && _states[cursor] != WordState.error) {
          _states.updateAll((k, v) => v == WordState.current ? WordState.idle : v);
          _states[cursor] = WordState.current;
        }
      case 'error':
        _replay = Map<String, dynamic>.from(ev['replay'] as Map);
        _correctLeft = ev['repeats'] as int;
        _states[ev['index'] as int] = WordState.error;
        _message = _errorText(ev['kind'] as String);
        setState(() {});
        await _playModelThenRepeat();
        return;
      case 'retry_started':
        for (var i = ev['start'] as int; i <= (ev['end'] as int); i++) {
          _states[i] = WordState.current;
        }
        _message = 'Your turn: recite it, then tap Done ($_correctLeft to go)';
      case 'retry_result':
        _correctLeft = ev['correct_repeats_left'] as int;
        if (ev['ok'] == true) {
          _message = _correctLeft > 0 ? 'Well done! Once more ($_correctLeft to go)' : 'Well done!';
        } else {
          _message = 'Not quite. Listen again.';
          setState(() {});
          await _playModelThenRepeat();
          return;
        }
      case 'resume':
        final r = _replay!;
        for (var i = r['start'] as int; i <= (r['end'] as int); i++) {
          _states[i] = WordState.correct;
        }
        _phase = _Phase.listening;
        _message = 'Carry on';
      case 'segment_done':
        _phase = _Phase.done;
        _message = 'Masha\'Allah! Surah complete.';
        await widget.store.completeLesson(widget.surah.info.number, xpGained: 20);
      case 'fatal':
        _phase = _Phase.failed;
        _message = ev['message'] as String?;
    }
    if (mounted) setState(() {});
  }

  Future<void> _playModelThenRepeat() async {
    final r = _replay!;
    setState(() => _phase = _Phase.playingModel);
    _client.muted = true;
    try {
      await _audio.playScope(
        scope: r['scope'] as String,
        words: _words,
        start: r['start'] as int,
        end: r['end'] as int,
        pace: widget.store.pace,
      );
    } catch (_) {
      // Offline or audio missing: still let the user repeat.
    }
    _client.muted = false;
    if (!mounted) return;
    setState(() {
      _phase = _Phase.repeating;
      _message = 'Your turn: recite it, then tap Done ($_correctLeft to go)';
    });
    _client.replayDone(); // ignored by the server if already in retry mode
  }

  String _errorText(String kind) => switch (kind) {
        'harakat' => 'Check the harakat on this word. Listen:',
        'letter' => 'A letter was off. Listen:',
        'missed' => 'A word was skipped. Listen to the passage:',
        _ => 'That word was different. Listen:',
      };

  @override
  void dispose() {
    _sub?.cancel();
    _client.dispose();
    _audio.dispose();
    _debugCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Recite · ${widget.surah.info.nameSimple}')),
      body: Column(
        children: [
          if (_message != null)
            Container(
              width: double.infinity,
              color: _phase == _Phase.playingModel || _states.containsValue(WordState.error)
                  ? scheme.errorContainer
                  : scheme.secondaryContainer,
              padding: const EdgeInsets.all(14),
              child: Text(_message!, textAlign: TextAlign.center),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: QuranText(
                words: _words,
                states: _states,
                verseEndAfter: _verseEnds,
                showTajweed: _phase != _Phase.listening,
              ),
            ),
          ),
          if (_mockServer && (_phase == _Phase.listening || _phase == _Phase.repeating))
            _DebugBar(
              controller: _debugCtrl,
              onSend: (final_) {
                _client.debugHypothesis(_debugCtrl.text, isFinal: final_);
                if (_phase == _Phase.repeating) _debugCtrl.clear();
              },
            ),
          SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: _controls())),
        ],
      ),
    );
  }

  Widget _controls() => switch (_phase) {
        _Phase.connecting => const CircularProgressIndicator(),
        _Phase.ready => FilledButton.icon(
            onPressed: _startListening, icon: const Icon(Icons.mic), label: const Text('Start reciting')),
        _Phase.listening => OutlinedButton.icon(
            onPressed: _client.stop, icon: const Icon(Icons.stop), label: const Text('Finish')),
        _Phase.playingModel => const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.volume_up), SizedBox(width: 8), Text('Listening to the model recitation'),
          ]),
        _Phase.repeating when _mockServer => const Text('Mock mode: type the repetition above and send'),
        _Phase.repeating => FilledButton.icon(
            onPressed: _client.attemptEnd, icon: const Icon(Icons.check), label: const Text('Done')),
        _Phase.done => FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Continue')),
        _Phase.failed => OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
      };
}

/// Shown only when the server runs the mock recogniser: type what you "recited".
class _DebugBar extends StatelessWidget {
  const _DebugBar({required this.controller, required this.onSend});
  final TextEditingController controller;
  final void Function(bool isFinal) onSend;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(labelText: 'Mock: everything recited so far', isDense: true),
            ),
          ),
          IconButton(onPressed: () => onSend(false), icon: const Icon(Icons.send)),
          IconButton(onPressed: () => onSend(true), icon: const Icon(Icons.done_all), tooltip: 'Final'),
        ]),
      );
}
