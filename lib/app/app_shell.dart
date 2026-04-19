import 'package:flutter/material.dart';

import '../application/session_controller.dart';
import '../application/workspace_controller.dart';
import '../features/connection/connection_panel.dart';
import '../features/console/workspace_console_panel.dart';
import '../features/quick_commands/quick_commands_panel.dart';
import '../features/send_panel/send_panel.dart';
import '../widgets/wheel_stepper.dart';

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
                      child: WorkspaceConsolePanel(controller: controller),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      flex: 2,
                      child: SendPanel(
                        controller: sendTarget,
                        targetSelector: _SendTargetSelector(
                          controller: controller,
                        ),
                      ),
                    ),
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
              return Row(
                children: [
                  _AnimatedConnectionSidePanel(
                    controller: controller,
                    session: activeSession,
                    width: _connectionWidth,
                    onResize: (delta) => setState(() {
                      _connectionWidth =
                          (_connectionWidth + delta).clamp(280, 520).toDouble();
                    }),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: WorkspaceConsolePanel(controller: controller),
                        ),
                        _HorizontalDragDivider(
                          onDrag: (delta) => setState(() {
                            _sendHeight = (_sendHeight - delta)
                                .clamp(160, 420)
                                .toDouble();
                          }),
                        ),
                        SizedBox(
                            height: _sendHeight,
                            child: SendPanel(
                              controller: sendTarget,
                              targetSelector: _SendTargetSelector(
                                controller: controller,
                              ),
                            )),
                      ],
                    ),
                  ),
                  _AnimatedQuickCommandsSidePanel(
                    controller: sendTarget,
                    width: _quickWidth,
                    onResize: (delta) => setState(() {
                      _quickWidth =
                          (_quickWidth - delta).clamp(260, 520).toDouble();
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
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: _SessionPager(controller: workspace),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ConnectionPanel(
            key: ValueKey<SessionController>(controller),
            controller: controller,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            occupiedSerialPorts: workspace.occupiedSerialPortsExcept(
              controller,
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
    return Row(
      children: [
        IconButton.outlined(
          tooltip: strings.previousSessionPage,
          onPressed:
              controller.canGoPrevious ? controller.previousSession : null,
          icon: const Icon(Icons.chevron_left),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: strings.nextSessionPage,
          onPressed: controller.canGoNext ? controller.nextSession : null,
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
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
        const SizedBox(width: 8),
        if (pageIndicator.isNotEmpty) ...[
          Text(
            pageIndicator,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(width: 8),
        ],
        _SessionActionButton(controller: controller),
      ],
    );
  }
}

class _SessionActionButton extends StatelessWidget {
  const _SessionActionButton({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.canAddSession) {
      return IconButton.outlined(
        tooltip: controller.strings.addSessionPage,
        onPressed: () {
          controller.addSession();
        },
        icon: const Icon(Icons.add),
      );
    }

    if (!controller.activeSession.isConnected) {
      return IconButton.outlined(
        tooltip: controller.strings.removeEmptySessionPage,
        onPressed: controller.canRemoveActiveSession
            ? controller.removeActiveSession
            : null,
        icon: const Icon(Icons.remove),
      );
    }

    return const SizedBox.square(dimension: 32);
  }
}

class _SendTargetSelector extends StatelessWidget {
  const _SendTargetSelector({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final connectedIndexes = controller.connectedSessionIndexes;
    final selectedValue = connectedIndexes.contains(controller.sendTargetIndex)
        ? controller.sendTargetIndex
        : null;
    return WheelStepper(
      enabled: connectedIndexes.length > 1,
      onStep: controller.stepSendTarget,
      child: DropdownButtonFormField<int>(
        key: ValueKey(
          'send-target-${controller.sendTargetIndex}-${connectedIndexes.join("|")}',
        ),
        initialValue: selectedValue,
        isExpanded: true,
        decoration: InputDecoration(labelText: controller.strings.sendTo),
        hint: Text(controller.strings.noConnectedTarget),
        items: [
          for (final i in connectedIndexes)
            DropdownMenuItem<int>(
              value: i,
              child: Text(
                controller.sessionLabel(i),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: connectedIndexes.isEmpty
            ? null
            : (index) {
                if (index != null) {
                  controller.setSendTargetIndex(index);
                }
              },
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
