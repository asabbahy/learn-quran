/// Data models for the bundled Quran text (built by tools/build_data.py).
library;

class TajweedSegment {
  const TajweedSegment(this.text, this.rule);
  final String text;
  final String? rule; // Quran.com tajweed class, e.g. "ghunnah", "madda_normal"

  factory TajweedSegment.fromJson(Map<String, dynamic> j) =>
      TajweedSegment(j['t'] as String, j['r'] as String?);
}

class MorphSegment {
  const MorphSegment({
    required this.form,
    required this.pos,
    required this.posName,
    this.root,
    this.lemma,
    this.kind,
    required this.features,
  });

  final String form;
  final String pos;
  final String posName;
  final String? root;
  final String? lemma;
  final String? kind; // prefix | stem | suffix
  final String features;

  factory MorphSegment.fromJson(Map<String, dynamic> j) => MorphSegment(
        form: j['form'] as String,
        pos: j['pos'] as String,
        posName: j['pos_name'] as String,
        root: j['root'] as String?,
        lemma: j['lemma'] as String?,
        kind: j['kind'] as String?,
        features: j['features'] as String? ?? '',
      );
}

/// Waqf (pause) signs as they appear inside Uthmani word text.
final _waqfMarks = RegExp('[ۖ-ۜ]');

class Word {
  const Word({
    required this.loc,
    required this.text,
    required this.tajweed,
    this.audio,
    this.root,
    this.morph = const [],
  });

  final String loc; // "surah:ayah:word"
  final String text;
  final List<TajweedSegment> tajweed;
  final String? audio; // relative to the word-audio CDN
  final String? root;
  final List<MorphSegment> morph;

  int get surah => int.parse(loc.split(':')[0]);
  int get ayah => int.parse(loc.split(':')[1]);
  int get position => int.parse(loc.split(':')[2]);

  String? get waqfMark => _waqfMarks.firstMatch(text)?.group(0);

  /// Tajweed rules on the final letters, which may carry into the next word.
  List<String> get endRules {
    final last = tajweed.isEmpty ? null : tajweed.last.rule;
    return last == null ? const [] : [last];
  }

  factory Word.fromJson(Map<String, dynamic> j) => Word(
        loc: j['loc'] as String,
        text: j['text'] as String,
        tajweed: (j['tajweed'] as List)
            .map((s) => TajweedSegment.fromJson(s as Map<String, dynamic>))
            .toList(),
        audio: j['audio'] as String?,
        root: j['root'] as String?,
        morph: ((j['morph'] as List?) ?? const [])
            .map((s) => MorphSegment.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class Verse {
  const Verse({required this.key, required this.number, required this.words});
  final String key;
  final int number;
  final List<Word> words;

  factory Verse.fromJson(Map<String, dynamic> j) => Verse(
        key: j['key'] as String,
        number: j['number'] as int,
        words: (j['words'] as List)
            .map((w) => Word.fromJson(w as Map<String, dynamic>))
            .toList(),
      );
}

class SurahInfo {
  const SurahInfo({
    required this.number,
    required this.nameArabic,
    required this.nameSimple,
    this.translatedName,
    required this.versesCount,
  });

  final int number;
  final String nameArabic;
  final String nameSimple;
  final String? translatedName;
  final int versesCount;

  factory SurahInfo.fromJson(Map<String, dynamic> j) => SurahInfo(
        number: j['number'] as int,
        nameArabic: j['name_arabic'] as String,
        nameSimple: j['name_simple'] as String,
        translatedName: j['translated_name'] as String?,
        versesCount: j['verses_count'] as int,
      );
}

class Surah {
  const Surah({required this.info, required this.riwaya, required this.verses, required this.rootIndex});
  final SurahInfo info;
  final String riwaya;
  final List<Verse> verses;

  /// root -> word locations in this surah (the full-Quran index comes later).
  final Map<String, List<String>> rootIndex;

  List<Word> get allWords => [for (final v in verses) ...v.words];

  factory Surah.fromJson(Map<String, dynamic> j) => Surah(
        info: SurahInfo.fromJson(j),
        riwaya: j['riwaya'] as String? ?? 'hafs',
        verses: (j['verses'] as List)
            .map((v) => Verse.fromJson(v as Map<String, dynamic>))
            .toList(),
        rootIndex: ((j['roots_in_surah'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, (v as List).cast<String>()),
        ),
      );
}
