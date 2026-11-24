import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/models.dart';
import '../tajweed/tajweed_colors.dart';

/// Live-check state of a word on the recite screen.
enum WordState { idle, current, correct, error }

/// Renders Uthmani words right-to-left with tajweed colours. Every word is
/// tappable, and can carry a live-check state (green / red / current).
class QuranText extends StatelessWidget {
  const QuranText({
    super.key,
    required this.words,
    this.onWordTap,
    this.states = const {},
    this.showTajweed = true,
    this.fontSize = 30,
    this.verseEndAfter = const {},
  });

  final List<Word> words;
  final void Function(Word word, int index)? onWordTap;
  final Map<int, WordState> states;
  final bool showTajweed;
  final double fontSize;

  /// Word indexes that end a verse; an ayah marker is drawn after them.
  final Set<int> verseEndAfter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = GoogleFonts.amiriQuran(
      fontSize: fontSize,
      height: 2.1,
      color: scheme.onSurface,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        spacing: fontSize * 0.28,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < words.length; i++) ...[
            _WordChip(
              word: words[i],
              state: states[i] ?? WordState.idle,
              base: base,
              showTajweed: showTajweed,
              onTap: onWordTap == null ? null : () => onWordTap!(words[i], i),
            ),
            if (verseEndAfter.contains(i))
              _AyahMarker(number: words[i].ayah, size: fontSize * 0.9),
          ],
        ],
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    required this.state,
    required this.base,
    required this.showTajweed,
    this.onTap,
  });

  final Word word;
  final WordState state;
  final TextStyle base;
  final bool showTajweed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color? bg, Color? fg) = switch (state) {
      WordState.correct => (const Color(0x2216A34A), const Color(0xFF15803D)),
      WordState.error => (const Color(0x33DC2626), const Color(0xFFB91C1C)),
      WordState.current => (Theme.of(context).colorScheme.primaryContainer, null),
      WordState.idle => (null, null),
    };

    final spans = [
      for (final seg in word.tajweed)
        TextSpan(
          text: seg.text,
          style: fg != null
              ? base.copyWith(color: fg)
              : (showTajweed && tajweedColor(seg.rule) != null)
                  ? base.copyWith(color: tajweedColor(seg.rule))
                  : base,
        ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Text.rich(TextSpan(children: spans), textDirection: TextDirection.rtl),
      ),
    );
  }
}

class _AyahMarker extends StatelessWidget {
  const _AyahMarker({required this.number, required this.size});
  final int number;
  final double size;

  static const _digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

  @override
  Widget build(BuildContext context) {
    final arabic = number.toString().split('').map((d) => _digits[int.parse(d)]).join();
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: size * 1.2,
      height: size * 1.2,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.5)),
      child: Text(arabic, style: TextStyle(fontSize: size * 0.5, color: color)),
    );
  }
}
