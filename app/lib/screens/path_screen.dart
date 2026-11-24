import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/models.dart';
import '../data/progress_store.dart';
import '../data/quran_repository.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// Duolingo-style path: start with Al-Fatiha, then the short surahs from the
/// end of the mushaf upwards. Each node unlocks after the one before it.
class PathScreen extends StatelessWidget {
  const PathScreen({super.key, required this.store});
  final ProgressStore store;

  static List<SurahInfo> order(List<SurahInfo> all) {
    final byNo = {for (final s in all) s.number: s};
    final seq = <int>[1, for (var n = 114; n >= 2; n--) n];
    return [for (final n in seq) if (byNo[n] != null) byNo[n]!];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Learn Quran'),
          actions: [
            _Stat(icon: Icons.local_fire_department, color: Colors.deepOrange, value: store.streak),
            _Stat(icon: Icons.bolt, color: Colors.amber.shade700, value: store.xp),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => SettingsScreen(store: store))),
            ),
          ],
        ),
        body: FutureBuilder<List<SurahInfo>>(
          future: QuranRepository.instance.index(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final path = order(snap.data!);
            if (path.isEmpty) return const _NoData();
            final done = store.completed;
            final firstOpen = path.indexWhere((s) => !done.contains(s.number));
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 24),
              itemCount: path.length,
              itemBuilder: (context, i) {
                final s = path[i];
                final status = done.contains(s.number)
                    ? _NodeStatus.done
                    : (i == firstOpen ? _NodeStatus.current : _NodeStatus.locked);
                // Zig-zag like a learning path.
                final offset = [0.0, 60.0, 0.0, -60.0][i % 4];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Transform.translate(
                    offset: Offset(offset, 0),
                    child: _Node(
                      info: s,
                      status: status,
                      onTap: status == _NodeStatus.locked
                          ? null
                          : () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => ReaderScreen(number: s.number, store: store))),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

enum _NodeStatus { done, current, locked }

class _Node extends StatelessWidget {
  const _Node({required this.info, required this.status, this.onTap});
  final SurahInfo info;
  final _NodeStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      _NodeStatus.done => const Color(0xFF16A34A),
      _NodeStatus.current => scheme.primary,
      _NodeStatus.locked => scheme.surfaceContainerHighest,
    };
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: status == _NodeStatus.current ? 84 : 72,
            height: status == _NodeStatus.current ? 84 : 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), offset: const Offset(0, 5))],
            ),
            alignment: Alignment.center,
            child: status == _NodeStatus.locked
                ? Icon(Icons.lock, color: scheme.outline)
                : status == _NodeStatus.done
                    ? const Icon(Icons.check, color: Colors.white, size: 34)
                    : Text(info.nameArabic,
                        style: GoogleFonts.amiriQuran(color: Colors.white, fontSize: 18)),
          ),
        ),
        const SizedBox(height: 6),
        Text(info.nameSimple, style: Theme.of(context).textTheme.labelLarge),
        Text('${info.versesCount} ayat', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.value});
  final IconData icon;
  final Color color;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(children: [Icon(icon, color: color), const SizedBox(width: 2), Text('$value')]),
      );
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No Quran data bundled yet.\n\nRun  python tools/build_data.py  from the repo root, '
            'then restart the app.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
