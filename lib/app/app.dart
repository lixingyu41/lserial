import 'dart:async';

import 'package:flutter/material.dart';

import '../application/session_controller.dart';
import '../platform/window_title.dart';
import 'app_shell.dart';

class CommToolApp extends StatefulWidget {
  const CommToolApp({super.key});

  @override
  State<CommToolApp> createState() => _CommToolAppState();
}

class _CommToolAppState extends State<CommToolApp> {
  late final SessionController controller;
  late String _title;

  @override
  void initState() {
    super.initState();
    controller = SessionController();
    _title = controller.windowTitle;
    controller.addListener(_syncWindowTitle);
    controller.initialize();
    _syncWindowTitle();
  }

  @override
  void dispose() {
    controller.removeListener(_syncWindowTitle);
    controller.dispose();
    super.dispose();
  }

  String? _appliedWindowTitle;

  void _syncWindowTitle() {
    final title = controller.windowTitle;
    if (_appliedWindowTitle == title) {
      return;
    }
    _appliedWindowTitle = title;
    if (mounted) {
      setState(() => _title = title);
    } else {
      _title = title;
    }
    unawaited(setAppWindowTitle(title));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: _title,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Title(
        title: _title,
        color: const Color(0xff256d85),
        child: AppShell(controller: controller),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff256d85),
      brightness: brightness,
    );
    const inputBorder = OutlineInputBorder(borderRadius: BorderRadius.zero);
    const squareShape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
    const buttonStyle = ButtonStyle(
      shape: WidgetStatePropertyAll<RoundedRectangleBorder>(squareShape),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xff202124)
          : const Color(0xffffffff),
      inputDecorationTheme: const InputDecorationTheme(
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder,
        errorBorder: inputBorder,
        focusedErrorBorder: inputBorder,
        isDense: true,
      ),
      filledButtonTheme: const FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: const OutlinedButtonThemeData(style: buttonStyle),
      textButtonTheme: const TextButtonThemeData(style: buttonStyle),
      iconButtonTheme: const IconButtonThemeData(style: buttonStyle),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          shape: WidgetStatePropertyAll<RoundedRectangleBorder>(squareShape),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll<RoundedRectangleBorder>(squareShape),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(shape: squareShape),
      dialogTheme: const DialogThemeData(shape: squareShape),
      chipTheme: ChipThemeData(
        shape: squareShape,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        shape: squareShape,
      ),
    );
  }
}
