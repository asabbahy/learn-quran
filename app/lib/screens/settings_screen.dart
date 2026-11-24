import 'package:flutter/material.dart';

import '../data/progress_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final ProgressStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          children: [
            const _Header('Reading (riwaya)'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'All ten readings are authentic in the traditional scholarly view; the app does not rank them. '
                'The checker always judges you against the reading you pick here.',
              ),
            ),
            RadioGroup<Riwaya>(
              groupValue: store.riwaya,
              onChanged: (v) => v == null ? null : store.setRiwaya(v),
              child: Column(children: [
                for (final r in Riwaya.values)
                  RadioListTile<Riwaya>(
                    value: r,
                    enabled: r.available,
                    title: Text(r.label),
                    subtitle: r.available ? null : const Text('Coming soon'),
                  ),
              ]),
            ),
            const _Header('Model recitation pace'),
            RadioGroup<Pace>(
              groupValue: store.pace,
              onChanged: (v) => v == null ? null : store.setPace(v),
              child: Column(children: [
                for (final p in Pace.values)
                  RadioListTile<Pace>(value: p, title: Text(p.label), subtitle: Text(p.hint)),
              ]),
            ),
            const _Header('Correction'),
            ListTile(
              title: const Text('Correct repetitions after a mistake'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => store.setRepeats(store.repeats - 1), icon: const Icon(Icons.remove)),
                Text('${store.repeats}', style: Theme.of(context).textTheme.titleMedium),
                IconButton(onPressed: () => store.setRepeats(store.repeats + 1), icon: const Icon(Icons.add)),
              ]),
            ),
            const _Header('Developer'),
            ListTile(
              title: const Text('Checker server'),
              subtitle: Text(store.serverUrl),
              trailing: const Icon(Icons.edit),
              onTap: () => _editUrl(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editUrl(BuildContext context) async {
    final ctrl = TextEditingController(text: store.serverUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Checker server URL'),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(hintText: 'ws://192.168.1.10:8000/ws/recite')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) await store.setServerUrl(url);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary)),
      );
}
