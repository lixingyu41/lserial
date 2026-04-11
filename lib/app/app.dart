import 'package:flutter/material.dart';

import '../application/session_controller.dart';
import 'app_shell.dart';

class CommToolApp extends StatefulWidget {
  const CommToolApp({super.key});

  @override
  State<CommToolApp> createState() => _CommToolAppState();
}

class _CommToolAppState extends State<CommToolApp> {
  late final SessionController controller;

  @override
  void initState() {
    super.initState();
    controller = SessionController();
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LSerial',
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: AppShell(controller: controller),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff256d85),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xff111418)
          : const Color(0xfff7f8fa),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }
}
