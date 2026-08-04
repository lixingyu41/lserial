import 'dart:async';

import 'package:flutter/material.dart';

import '../application/workspace_controller.dart';
import '../mcp/lserial_mcp_service.dart';
import '../mcp/lserial_mcp_service_base.dart';
import '../platform/window_title.dart';
import 'app_shell.dart';

class CommToolApp extends StatefulWidget {
  const CommToolApp({super.key});

  @override
  State<CommToolApp> createState() => _CommToolAppState();
}

class _CommToolAppState extends State<CommToolApp> {
  late final WorkspaceController controller;
  late final LSerialMcpService mcpService;
  late String _title;

  @override
  void initState() {
    super.initState();
    controller = WorkspaceController();
    mcpService = createLSerialMcpService(controller);
    controller.attachMcpService(mcpService);
    _title = controller.windowTitle;
    controller.addListener(_syncWindowTitle);
    unawaited(_initialize());
    _syncWindowTitle();
  }

  @override
  void dispose() {
    controller.removeListener(_syncWindowTitle);
    mcpService.dispose();
    controller.dispose();
    super.dispose();
  }

  String? _appliedWindowTitle;

  Future<void> _initialize() async {
    await controller.initialize();
    await mcpService.setEnabled(controller.mcpEnabled);
  }

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
        color: const Color(0xff007aff),
        child: AppShell(controller: controller),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff007aff),
      brightness: brightness,
      primary: const Color(0xff007aff),
      secondary: const Color(0xff34c759),
      tertiary: const Color(0xffff9500),
      error: const Color(0xffff3b30),
      surface: isDark ? const Color(0xff1c1c1e) : const Color(0xffffffff),
      surfaceContainerHighest:
          isDark ? const Color(0xff2c2c2e) : const Color(0xfff2f2f7),
      outline: isDark ? const Color(0xff636366) : const Color(0xff8e8e93),
      outlineVariant:
          isDark ? const Color(0xff3a3a3c) : const Color(0xffd1d1d6),
    );
    const radius = BorderRadius.all(Radius.circular(8));
    const inputBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(width: 0.8),
    );
    const roundedShape = RoundedRectangleBorder(borderRadius: radius);
    final baseTextTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    ).textTheme.apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: const <String>['Noto Sans SC'],
    );
    final textTheme = baseTextTheme.copyWith(
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 14,
        letterSpacing: 0,
        height: 1.35,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 13,
        letterSpacing: 0,
        height: 1.35,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 12,
        letterSpacing: 0,
        height: 1.32,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 11,
        letterSpacing: 0,
      ),
    );
    final buttonPadding = WidgetStateProperty.all(
      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    );
    final buttonShape =
        WidgetStateProperty.all<RoundedRectangleBorder>(roundedShape);
    final minimumButtonSize = WidgetStateProperty.all(const Size(32, 32));
    final filledButtonStyle = ButtonStyle(
      minimumSize: minimumButtonSize,
      padding: buttonPadding,
      shape: buttonShape,
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.12);
        }
        return colorScheme.primary;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.38);
        }
        return Colors.white;
      }),
    );
    final outlinedButtonStyle = ButtonStyle(
      minimumSize: minimumButtonSize,
      padding: buttonPadding,
      shape: buttonShape,
      side: WidgetStateProperty.resolveWith((states) {
        final alpha = states.contains(WidgetState.disabled) ? 0.25 : 1.0;
        return BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: alpha),
          width: 0.8,
        );
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return colorScheme.primary.withValues(alpha: 0.12);
        }
        return colorScheme.surfaceContainerHighest.withValues(alpha: 0.72);
      }),
    );
    final textButtonStyle = ButtonStyle(
      minimumSize: minimumButtonSize,
      padding: buttonPadding,
      shape: buttonShape,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      scaffoldBackgroundColor:
          isDark ? const Color(0xff1c1c1e) : const Color(0xfff5f5f7),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 0.8,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: Color(0xff007aff), width: 1.2),
        ),
        errorBorder: inputBorder,
        focusedErrorBorder: inputBorder,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        labelStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
          letterSpacing: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: filledButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: outlinedButtonStyle),
      textButtonTheme: TextButtonThemeData(style: textButtonStyle),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size.square(32)),
          iconSize: WidgetStateProperty.all(18),
          padding: WidgetStateProperty.all(EdgeInsets.zero),
          shape: buttonShape,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.primary.withValues(alpha: 0.12);
            }
            return Colors.transparent;
          }),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xff34c759);
          }
          return colorScheme.outlineVariant;
        }),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          shape: WidgetStatePropertyAll<RoundedRectangleBorder>(roundedShape),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll<RoundedRectangleBorder>(roundedShape),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(shape: roundedShape),
      dialogTheme: const DialogThemeData(shape: roundedShape),
      chipTheme: ChipThemeData(
        shape: roundedShape,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        shape: roundedShape,
      ),
    );
  }
}
