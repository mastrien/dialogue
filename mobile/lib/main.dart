import 'package:flutter/material.dart';
import 'models.dart';
import 'rust_bridge.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustBridge.init();
  final settings = await RustBridge.getSettings();
  runApp(DialogueApp(initialSettings: settings));
}

class DialogueApp extends StatefulWidget {
  final AppSettings initialSettings;

  const DialogueApp({super.key, required this.initialSettings});

  @override
  State<DialogueApp> createState() => _DialogueAppState();
}

class _DialogueAppState extends State<DialogueApp> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _settings.theme == 'dark';
    return MaterialApp(
      title: 'Dialogue',
      debugShowCheckedModeBanner: false,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          surface: const Color(0xFF09090B),
        ),
        scaffoldBackgroundColor: const Color(0xFF09090B),
      ),
      home: HomeScreen(
        settings: _settings,
        onSettingsChanged: (updated) => setState(() => _settings = updated),
      ),
    );
  }
}
