import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/models.dart';
import '../tajweed/tajweed_colors.dart';
import 'quran_text.dart';

/// The language layer for one word: root, morphology, tajweed on the word, and
/// other occurrences of the root. Lexicon meanings (al-Mufradat, Lisan al-Arab)
/// slot in under "Meaning" once their licensing is settled.
Future<void> showWordSheet(BuildContext context, Word word, Surah surah) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      builder: (context, controller) => _WordSheet(word: word, surah: surah, controller: controller),
    ),
  );
}

class _WordSheet extends StatelessWidget {
  const _WordSheet({required this.word, required this.surah, required this.controller});
  final Word word;
  final Surah surah;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rules = {for (final s in word.tajweed) if (s.rule != null) s.rule!};
    final occurrences = word.root == null ? const <String>[] : (surah.rootIndex[word.root] ?? const []);
    final byLoc = {for (final w in surah.allWords) w.loc: w};

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Center(child: QuranText(words: [word], fontSize: 44)),
        Center(child: Text('${surah.info.nameSimple} ${word.surah}:${word.ayah}, word ${word.position}', style: t.bodySmall)),
        const SizedBox(height: 16),

        _Section('Root', child: word.root == null
            ? const _Missing('Root data comes from the Quranic Arabic Corpus. Build the data with --morphology to fill this in.')
            : Text(word.root!, textDirection: TextDirection.rtl, style: GoogleFonts.amiriQuran(fontSize: 30))),

        if (word.morph.isNotEmpty)
          _Section('Morphology', child: Column(
            children: [
              for (final m in word.morph)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Text(m.form, textDirection: TextDirection.rtl, style: GoogleFonts.amiriQuran(fontSize: 22)),
                  title: Text([m.kind, m.posName].whereType<String>().join(' · ')),
                  subtitle: Text([
                    if (m.lemma != null) 'lemma ${m.lemma}',
                    m.features,
                  ].join('  ')),
                ),
            ],
          )),

        const _Section('Meaning', child: _Missing(
            'Classical lexicon (al-Mufradat by al-Raghib al-Isfahani, then Lisan al-Arab) goes here once the text licences are confirmed.')),

        if (rules.isNotEmpty)
          _Section('Tajweed in this word', child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in rules)
                Chip(
                  avatar: CircleAvatar(backgroundColor: tajweedColor(r), radius: 7),
                  label: Text(tajweedRules[r]?.label ?? r),
                ),
            ],
          )),

        if (occurrences.length > 1)
          _Section('Same root in this surah', child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final loc in occurrences)
                if (byLoc[loc] != null)
                  ActionChip(
                    label: Text('${byLoc[loc]!.text}  ${loc.split(':').take(2).join(':')}',
                        textDirection: TextDirection.rtl),
                    onPressed: null,
                  ),
            ],
          )),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          child,
        ]),
      );
}

class _Missing extends StatelessWidget {
  const _Missing(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontStyle: FontStyle.italic));
}
