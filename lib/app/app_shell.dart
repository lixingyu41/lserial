import 'package:flutter/material.dart';

import '../application/session_controller.dart';
import '../features/connection/connection_panel.dart';
import '../features/console/console_panel.dart';
import '../features/quick_commands/quick_commands_panel.dart';
import '../features/send_panel/send_panel.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final SessionController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  double _connectionWidth = 330;
  double _connectionTopHeight = 210;
  double _sendHeight = 230;
  double _quickWidth = 300;
  double _quickBottomHeight = 240;

  SessionController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 980) {
                final topHeight = _clampPanelExtent(
                  _connectionTopHeight,
                  min: 120,
                  max: constraints.maxHeight * 0.28,
                );
                final quickHeight = _clampPanelExtent(
                  _quickBottomHeight,
                  min: 120,
                  max: constraints.maxHeight * 0.22,
                );
                return Column(
                  children: [
                    _AnimatedConnectionTopPanel(
                      controller: controller,
                      height: topHeight,
                      onResize: (delta) => setState(() {
                        _connectionTopHeight = (_connectionTopHeight + delta)
                            .clamp(150, 420)
                            .toDouble();
                      }),
                    ),
                    Expanded(
                      flex: 4,
                      child: ConsolePanel(controller: controller),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      flex: 2,
                      child: SendPanel(controller: controller),
                    ),
                    _AnimatedQuickCommandsBottomPanel(
                      controller: controller,
                      height: quickHeight,
                      onResize: (delta) => setState(() {
                        _quickBottomHeight = (_quickBottomHeight - delta)
                            .clamp(150, 420)
                            .toDouble();
                      }),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  _AnimatedConnectionSidePanel(
                    controller: controller,
                    width: _connectionWidth,
                    onResize: (delta) => setState(() {
                      _connectionWidth =
                          (_connectionWidth + delta).clamp(260, 520).toDouble();
                    }),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: ConsolePanel(controller: controller)),
                        _HorizontalDragDivider(
                          onDrag: (delta) => setState(() {
                            _sendHeight = (_sendHeight - delta)
                                .clamp(150, 420)
                                .toDouble();
                          }),
                        ),
                        SizedBox(
                            height: _sendHeight,
                            child: SendPanel(controller: controller)),
                      ],
                    ),
                  ),
                  _AnimatedQuickCommandsSidePanel(
                    controller: controller,
                    width: _quickWidth,
                    onResize: (delta) => setState(() {
                      _quickWidth =
                          (_quickWidth - delta).clamp(240, 520).toDouble();
                    }),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  double _clampPanelExtent(
    double value, {
    required double min,
    required double max,
  }) {
    if (!max.isFinite || max <= 0) {
      return 0;
    }
    final safeMin = min > max ? max : min;
    return value.clamp(safeMin, max).toDouble();
  }
}

class _AnimatedConnectionTopPanel extends StatelessWidget {
  const _AnimatedConnectionTopPanel({
    required this.controller,
    required this.height,
    required this.onResize,
  });

  final SessionController controller;
  final double height;
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ClipRect(
          child: SizeTransition(
            axisAlignment: -1,
            sizeFactor: curved,
            child: child,
          ),
        );
      },
      child: Column(
        key: const ValueKey('connection-open-top'),
        children: [
          SizedBox(
            height: height,
            child: ConnectionPanel(controller: controller),
          ),
          _HorizontalDragDivider(onDrag: onResize),
        ],
      ),
    );
  }
}

class _AnimatedConnectionSidePanel extends StatelessWidget {
  const _AnimatedConnectionSidePanel({
    required this.controller,
    required this.width,
    required this.onResize,
  });

  final SessionController controller;
  final double width;
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ClipRect(
          child: SizeTransition(
            axis: Axis.horizontal,
            axisAlignment: -1,
            sizeFactor: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ),
        );
      },
      child: Row(
        key: const ValueKey('connection-open-side'),
        children: [
          SizedBox(
            width: width,
            child: ConnectionPanel(controller: controller),
          ),
          _VerticalDragDivider(onDrag: onResize),
        ],
      ),
    );
  }
}

class _AnimatedQuickCommandsBottomPanel extends StatelessWidget {
  const _AnimatedQuickCommandsBottomPanel({
    required this.controller,
    required this.height,
    required this.onResize,
  });

  final SessionController controller;
  final double height;
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ClipRect(
          child: SizeTransition(
            axisAlignment: 1,
            sizeFactor: curved,
            child: child,
          ),
        );
      },
      child: Column(
        key: const ValueKey('quick-commands-open-bottom'),
        children: [
          _HorizontalDragDivider(onDrag: onResize),
          SizedBox(
            height: height,
            child: QuickCommandsPanel(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _AnimatedQuickCommandsSidePanel extends StatelessWidget {
  const _AnimatedQuickCommandsSidePanel({
    required this.controller,
    required this.width,
    required this.onResize,
  });

  final SessionController controller;
  final double width;
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ClipRect(
          child: SizeTransition(
            axis: Axis.horizontal,
            axisAlignment: 1,
            sizeFactor: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ),
        );
      },
      child: Row(
        key: const ValueKey('quick-commands-open'),
        children: [
          _VerticalDragDivider(onDrag: onResize),
          SizedBox(
            width: width,
            child: QuickCommandsPanel(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _VerticalDragDivider extends StatelessWidget {
  const _VerticalDragDivider({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: 7,
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalDragDivider extends StatelessWidget {
  const _HorizontalDragDivider({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: SizedBox(
          height: 7,
          child: Center(
            child: Container(
              height: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}
