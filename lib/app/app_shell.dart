import 'package:flutter/material.dart';

import '../application/session_controller.dart';
import '../application/workspace_controller.dart';
import '../features/connection/connection_panel.dart';
import '../features/console/workspace_console_panel.dart';
import '../features/quick_commands/quick_commands_panel.dart';
import '../features/send_panel/send_panel.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  double _connectionWidth = 318;
  double _connectionTopHeight = 220;
  double _sendHeight = 220;
  double _quickWidth = 292;
  double _quickBottomHeight = 236;

  WorkspaceController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final activeSession = controller.activeSession;
        final sendTarget = controller.sendTarget;
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
                    if (controller.showConnectionPanel)
                      _AnimatedConnectionTopPanel(
                        controller: controller,
                        session: activeSession,
                        height: topHeight,
                        onResize: (delta) => setState(() {
                          _connectionTopHeight = (_connectionTopHeight + delta)
                              .clamp(160, 440)
                              .toDouble();
                        }),
                      ),
                    Expanded(
                      flex: 4,
                      child: RepaintBoundary(
                        child: WorkspaceConsolePanel(
                          controller: controller,
                          panelsStackVertically: true,
                        ),
                      ),
                    ),
                    if (controller.showSendPanel) ...[
                      const Divider(height: 1),
                      Expanded(
                        flex: 2,
                        child: RepaintBoundary(
                          child: SendPanel(controller: sendTarget),
                        ),
                      ),
                    ],
                    if (controller.showQuickCommandsPanel)
                      _AnimatedQuickCommandsBottomPanel(
                        controller: sendTarget,
                        height: quickHeight,
                        onResize: (delta) => setState(() {
                          _quickBottomHeight = (_quickBottomHeight - delta)
                              .clamp(160, 440)
                              .toDouble();
                        }),
                      ),
                  ],
                );
              }
              final occupiedConnectionWidth = controller.showConnectionPanel
                  ? _connectionWidth + _panelDividerHitExtent
                  : 0.0;
              final maxQuickWidth =
                  constraints.maxWidth -
                  occupiedConnectionWidth -
                  _panelDividerHitExtent;
              final quickWidth = _clampPanelExtent(
                _quickWidth,
                min: 260,
                max: maxQuickWidth,
              );
              return Row(
                children: [
                  if (controller.showConnectionPanel)
                    _AnimatedConnectionSidePanel(
                      controller: controller,
                      session: activeSession,
                      width: _connectionWidth,
                      onResize: (delta) => setState(() {
                        _connectionWidth = (_connectionWidth + delta)
                            .clamp(280, 520)
                            .toDouble();
                      }),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: RepaintBoundary(
                            child: WorkspaceConsolePanel(
                              controller: controller,
                              panelsStackVertically: false,
                            ),
                          ),
                        ),
                        if (controller.showSendPanel) ...[
                          _HorizontalDragDivider(
                            onDrag: (delta) => setState(() {
                              _sendHeight = (_sendHeight - delta)
                                  .clamp(160, 420)
                                  .toDouble();
                            }),
                          ),
                          SizedBox(
                            height: _sendHeight,
                            child: RepaintBoundary(
                              child: SendPanel(controller: sendTarget),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (controller.showQuickCommandsPanel)
                    _AnimatedQuickCommandsSidePanel(
                      controller: sendTarget,
                      width: quickWidth,
                      onResize: (delta) => setState(() {
                        _quickWidth = (_quickWidth - delta)
                            .clamp(
                              maxQuickWidth < 260 ? maxQuickWidth : 260,
                              maxQuickWidth,
                            )
                            .toDouble();
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
    required this.session,
    required this.height,
    required this.onResize,
  });

  final WorkspaceController controller;
  final SessionController session;
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
            alignment: AlignmentDirectional.topStart,
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
            child: _ConnectionPageArea(
              workspace: controller,
              controller: session,
            ),
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
    required this.session,
    required this.width,
    required this.onResize,
  });

  final WorkspaceController controller;
  final SessionController session;
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
            alignment: AlignmentDirectional.topStart,
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
            child: _ConnectionPageArea(
              workspace: controller,
              controller: session,
            ),
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
            alignment: AlignmentDirectional.bottomStart,
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
            child: RepaintBoundary(
              child: QuickCommandsPanel(controller: controller),
            ),
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
            alignment: AlignmentDirectional.topEnd,
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
            child: RepaintBoundary(
              child: QuickCommandsPanel(controller: controller),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionPageArea extends StatelessWidget {
  const _ConnectionPageArea({
    required this.workspace,
    required this.controller,
  });

  final WorkspaceController workspace;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SessionPager(controller: workspace),
        Expanded(
          child: RepaintBoundary(
            child: ConnectionPanel(
              key: ValueKey<SessionController>(controller),
              workspaceController: workspace,
              controller: controller,
              padding: EdgeInsets.zero,
              occupiedSerialPorts: workspace.occupiedSerialPortsExcept(
                controller,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionPager extends StatelessWidget {
  const _SessionPager({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeSession;
    final strings = controller.strings;
    final pageIndicator = controller.pageIndicator;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _SessionPagerButton(
            tooltip: strings.previousSessionPage,
            onPressed: controller.canGoPrevious
                ? controller.previousSession
                : null,
            icon: Icons.chevron_left,
          ),
          const _PanelSeparator(),
          _SessionPagerButton(
            tooltip: strings.nextSessionPage,
            onPressed: controller.canGoNext ? controller.nextSession : null,
            icon: Icons.chevron_right,
          ),
          const _PanelSeparator(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Text(
                    active.sourceLabel,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ),
          ),
          if (pageIndicator.isNotEmpty) ...[
            const _PanelSeparator(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                pageIndicator,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
          const _PanelSeparator(),
          _SessionActionButton(controller: controller),
        ],
      ),
    );
  }
}

class _SessionPagerButton extends StatelessWidget {
  const _SessionPagerButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(40),
          fixedSize: const Size.square(40),
          padding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _SessionActionButton extends StatelessWidget {
  const _SessionActionButton({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.canAddSession) {
      return _SessionPagerButton(
        tooltip: controller.strings.addSessionPage,
        onPressed: () {
          controller.addSession();
        },
        icon: Icons.add,
      );
    }

    if (!controller.activeSession.isConnected) {
      return _SessionPagerButton(
        tooltip: controller.strings.removeEmptySessionPage,
        onPressed: controller.canRemoveActiveSession
            ? controller.removeActiveSession
            : null,
        icon: Icons.remove,
      );
    }

    return const SizedBox.square(dimension: 40);
  }
}

class _PanelSeparator extends StatelessWidget {
  const _PanelSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(color: Theme.of(context).dividerColor),
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
          width: _panelDividerHitExtent,
          height: double.infinity,
          child: Center(
            child: SizedBox(
              width: 1,
              height: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                ),
              ),
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
          width: double.infinity,
          height: _panelDividerHitExtent,
          child: Center(
            child: SizedBox(
              width: double.infinity,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _panelDividerHitExtent = 9.0;
