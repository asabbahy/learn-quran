import 'package:flutter/material.dart';

import 'data/progress_store.dart';
import 'screens/path_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ProgressStore.load();
  runApp(LearnQuranApp(store: store));
}

class LearnQuranApp extends StatelessWidget {
  const LearnQuranApp({super.key, required this.store});
  final ProgressStore store;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E); // deep teal
    return MaterialApp(
      title: 'Learn Quran',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: PathScreen(store: store),
    );
  }
}
