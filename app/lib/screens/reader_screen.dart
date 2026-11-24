import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/progress_store.dart';
import '../data/quran_repository.dart';
import '../tajweed/tajweed_colors.dart';
import '../widgets/quran_text.dart';
import '../widgets/word_sheet.dart';
import 'recite_screen.dart';

/// Read a surah with full tashkil and tajweed colours; tap any word to open
/// the language layer.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.number, required this.store});
  final int number;
  final ProgressStore store;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final Future<Surah> _surah = QuranRepository.instance.surah(widget.number);
  bool _tajweed = true;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Surah>(
      future: _surah,
      builder: (context, snap) {
        final s = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(s == null ? '' : '${s.info.nameSimple}  ${s.info.nameArabic}'),
            actions: [
              IconButton(
                tooltip: 'Tajweed colours',
                icon: Icon(_tajweed ? Icons.palette : Icons.palette_outlined),
                onPressed: () => setState(() => _tajweed = !_tajweed),
              ),
              IconButton(
                tooltip: 'Colour key',
                icon: const Icon(Icons.info_outline),
                onPressed: () => _legend(context),
              ),
            ],
          ),
          floatingActionButton: s == null
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.mic),
                  label: const Text('Recite'),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ReciteScreen(surah: s, store: widget.store))),
                ),
          body: switch (snap) {
            AsyncSnapshot(hasError: true) => Center(child: Text('Could not load surah: ${snap.error}')),
            AsyncSnapshot(hasData: false) => const Center(child: CircularProgressIndicator()),
            _ => ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                children: [
                  for (final v in s!.verses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: QuranText(
                        words: v.words,
                        showTajweed: _tajweed,
                        verseEndAfter: {v.words.length - 1},
                        onWordTap: (w, _) => showWordSheet(context, w, s),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text('Riwaya: Hafs \'an \'Asim · text: Quran.com (Uthmani)',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
          },
        );
      },
    );
  }

  void _legend(BuildContext context) => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            for (final r in tajweedRules.values)
              ListTile(
                dense: true,
                leading: CircleAvatar(backgroundColor: r.color, radius: 9),
                title: Text(r.label),
              ),
          ],
        ),
      );
}
