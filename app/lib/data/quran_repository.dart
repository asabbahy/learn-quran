import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Loads the bundled JSON produced by tools/build_data.py.
class QuranRepository {
  QuranRepository._();
  static final instance = QuranRepository._();

  List<SurahInfo>? _index;
  final _cache = <int, Surah>{};

  /// Returns an empty list if the data hasn't been built yet.
  Future<List<SurahInfo>> index() async {
    if (_index != null) return _index!;
    try {
      final raw = await rootBundle.loadString('assets/quran/index.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _index = (j['surahs'] as List)
          .map((s) => SurahInfo.fromJson(s as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _index = const [];
    }
    return _index!;
  }

  Future<Surah> surah(int number) async {
    final hit = _cache[number];
    if (hit != null) return hit;
    final raw = await rootBundle.loadString('assets/quran/surah_$number.json');
    final s = Surah.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    _cache[number] = s;
    return s;
  }
}
