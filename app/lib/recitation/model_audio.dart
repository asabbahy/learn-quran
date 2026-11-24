import 'package:just_audio/just_audio.dart';

import '../data/models.dart';
import '../data/progress_store.dart';

/// Plays the expert model recitation for the stretch the user got wrong.
///
/// * word   -> Quran.com word-by-word audio (Hafs)
/// * phrase -> the words in sequence
/// * segment-> the full ayah(s) from an everyayah.com reciter for the chosen pace
///
/// TODO: per-riwaya reciters, and timestamp-sliced segments (Quran.com
/// recitation segments API) instead of whole ayahs.
class ModelAudio {
  final _player = AudioPlayer();

  static const _wordCdn = 'https://audio.qurancdn.com/';

  // everyayah.com folder per pace (Hafs). Verify the folder names against
  // https://everyayah.com/recitations_pages.html before release.
  static const _ayahFolders = {
    Pace.tahqiq: 'Husary_128kbps_Mujawwad',
    Pace.tadwir: 'Husary_128kbps',
    Pace.hadr: 'Abdullah_Basfar_192kbps',
  };

  Future<void> playScope({
    required String scope,
    required List<Word> words,
    required int start,
    required int end,
    required Pace pace,
  }) async {
    final List<AudioSource> sources;
    if (scope == 'segment') {
      final ayahs = {for (var i = start; i <= end; i++) (words[i].surah, words[i].ayah)};
      sources = [
        for (final (s, a) in ayahs)
          AudioSource.uri(Uri.parse(
              'https://everyayah.com/data/${_ayahFolders[pace]}/'
              '${s.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}.mp3')),
      ];
    } else {
      sources = [
        for (var i = start; i <= end; i++)
          if (words[i].audio != null) AudioSource.uri(Uri.parse('$_wordCdn${words[i].audio}')),
      ];
    }
    if (sources.isEmpty) return;
    await _player.setAudioSource(ConcatenatingAudioSource(children: sources));
    await _player.play();
    await _player.processingStateStream.firstWhere((s) => s == ProcessingState.completed);
    await _player.stop();
  }

  Future<void> dispose() => _player.dispose();
}
