import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/data/models.dart';

void main() {
  test('word parses location, end rules and waqf mark', () {
    final w = Word.fromJson({
      'loc': '2:2:5',
      'text': 'كَتَبَۛ',
      'tajweed': [
        {'t': 'كَتَ'},
        {'t': 'بَۛ', 'r': 'qalaqah'},
      ],
    });
    expect([w.surah, w.ayah, w.position], [2, 2, 5]);
    expect(w.endRules, ['qalaqah']);
    expect(w.waqfMark, 'ۛ');
  });
}
