import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/models.dart';

/// Streams the microphone to the checker server and surfaces its events.
/// Protocol: see server/app/main.py.
class ReciteClient {
  ReciteClient(this.serverUrl);
  final String serverUrl;

  WebSocketChannel? _ch;
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _mic;
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// While true, mic audio is not sent (e.g. while the model recitation plays,
  /// so the reciter's voice isn't checked as the user's).
  bool muted = false;

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> connect({
    required List<Word> words,
    required String riwaya,
    required int repeats,
  }) async {
    final ch = WebSocketChannel.connect(Uri.parse(serverUrl));
    await ch.ready;
    _ch = ch;
    ch.stream.listen(
      (msg) {
        if (msg is String) _events.add(jsonDecode(msg) as Map<String, dynamic>);
      },
      onError: (Object e) => _events.add({'type': 'fatal', 'message': '$e'}),
      onDone: () => _events.add({'type': 'closed'}),
    );

    final verseEnds = <int>{};
    for (var i = 0; i < words.length; i++) {
      if (i == words.length - 1 || words[i + 1].ayah != words[i].ayah) verseEnds.add(i);
    }
    _send({
      'type': 'start',
      'riwaya': riwaya,
      'repeats': repeats,
      'words': [
        for (var i = 0; i < words.length; i++)
          {
            'loc': words[i].loc,
            'text': words[i].text,
            'end_rules': words[i].endRules,
            'waqf_after': words[i].waqfMark,
            'ayah_end': verseEnds.contains(i),
          }
      ],
    });
  }

  Future<bool> startMic() async {
    if (!await _recorder.hasPermission()) return false;
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
    ));
    _mic = stream.listen((chunk) {
      if (!muted) _ch?.sink.add(chunk);
    });
    return true;
  }

  void replayDone() => _send({'type': 'replay_done'});
  void attemptEnd() => _send({'type': 'attempt_end'});
  void stop() => _send({'type': 'stop'});

  /// Mock-recogniser mode: send text instead of audio.
  void debugHypothesis(String text, {bool isFinal = false}) =>
      _send({'type': 'debug_hypothesis', 'text': text, 'final': isFinal});

  void _send(Map<String, dynamic> m) => _ch?.sink.add(jsonEncode(m));

  Future<void> dispose() async {
    await _mic?.cancel();
    if (await _recorder.isRecording()) await _recorder.stop();
    await _recorder.dispose();
    await _ch?.sink.close();
    await _events.close();
  }
}
