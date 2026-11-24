import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reading and pace options. The ten readings / twenty riwayat get added here
/// as text, audio and checker support land for each one.
enum Riwaya {
  hafs('Hafs \'an \'Asim', true),
  warsh('Warsh \'an Nafi\'', false),
  qalun('Qalun \'an Nafi\'', false),
  duri('Al-Duri \'an Abi \'Amr', false);

  const Riwaya(this.label, this.available);
  final String label;
  final bool available; // text + audio + checker ready
}

enum Pace {
  tahqiq('Tahqiq', 'Slow, for learning'),
  tadwir('Tadwir', 'Medium'),
  hadr('Hadr', 'Fast');

  const Pace(this.label, this.hint);
  final String label;
  final String hint;
}

/// XP, streak, finished lessons and settings, kept on the device.
class ProgressStore extends ChangeNotifier {
  ProgressStore._(this._prefs);
  final SharedPreferences _prefs;

  static Future<ProgressStore> load() async =>
      ProgressStore._(await SharedPreferences.getInstance());

  int get xp => _prefs.getInt('xp') ?? 0;
  int get streak => _prefs.getInt('streak') ?? 0;
  Set<int> get completed =>
      (_prefs.getStringList('completed') ?? const []).map(int.parse).toSet();

  Riwaya get riwaya => Riwaya.values.byName(_prefs.getString('riwaya') ?? 'hafs');
  Pace get pace => Pace.values.byName(_prefs.getString('pace') ?? 'tahqiq');
  int get repeats => _prefs.getInt('repeats') ?? 2;
  String get serverUrl => _prefs.getString('serverUrl') ?? 'ws://10.0.2.2:8000/ws/recite';

  Future<void> setRiwaya(Riwaya r) async {
    await _prefs.setString('riwaya', r.name);
    notifyListeners();
  }

  Future<void> setPace(Pace p) async {
    await _prefs.setString('pace', p.name);
    notifyListeners();
  }

  Future<void> setRepeats(int n) async {
    await _prefs.setInt('repeats', n.clamp(1, 5));
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    await _prefs.setString('serverUrl', url.trim());
    notifyListeners();
  }

  /// Call when a lesson is finished. Updates XP and the daily streak.
  Future<void> completeLesson(int surah, {int xpGained = 10}) async {
    await _prefs.setInt('xp', xp + xpGained);
    await _prefs.setStringList(
        'completed', {...completed, surah}.map((e) => '$e').toList());

    final today = _day(DateTime.now());
    final last = _prefs.getInt('lastActiveDay');
    if (last == null || today - last > 1) {
      await _prefs.setInt('streak', 1);
    } else if (today - last == 1) {
      await _prefs.setInt('streak', streak + 1);
    }
    await _prefs.setInt('lastActiveDay', today);
    notifyListeners();
  }

  static int _day(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;
}
