import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../storage/log_buffer.dart';
import 'frame_list_view.dart';

class ConsolePanel extends StatefulWidget {
  const ConsolePanel({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final TextEditingController search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<LogSnapshot>(
            valueListenable: widget.controller.displaySnapshot,
            builder: (context, snapshot, _) {
              return FrameListView(
                snapshot: snapshot,
                controller: widget.controller,
                filter: search.text,
              );
            },
          ),
        ),
        const Divider(height: 1),
        _ConsoleToolbar(controller: widget.controller, search: search),
      ],
    );
  }
}

class _ConsoleToolbar extends StatelessWidget {
  const _ConsoleToolbar({
    required this.controller,
    required this.search,
  });

  final SessionController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchField = _SearchField(
            controller: controller,
            search: search,
          );
          final rightActions = _RightActions(controller: controller);

          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: rightActions,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 220, child: searchField),
              const Spacer(),
              rightActions,
            ],
          );
        },
      ),
    );
  }
}

class _RightActions extends StatelessWidget {
  const _RightActions({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: controller.clearLog,
          icon: const Icon(Icons.clear_all),
          label: const Text('清空'),
        ),
        const SizedBox(width: 8),
        _LogSettingsButton(controller: controller),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.search,
  });

  final SessionController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: search,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        labelText: '搜索过滤',
      ),
      onChanged: (_) {
        controller.displaySnapshot.value = controller.logBuffer.snapshot(
          paused: controller.pauseDisplay,
        );
      },
    );
  }
}

class _LogSettingsButton extends StatefulWidget {
  const _LogSettingsButton({required this.controller});

  final SessionController controller;

  @override
  State<_LogSettingsButton> createState() => _LogSettingsButtonState();
}

class _LogSettingsButtonState extends State<_LogSettingsButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton.outlined(
        tooltip: '日志设置',
        onPressed: _toggleEntry,
        icon: const Icon(Icons.settings),
      ),
    );
  }

  void _toggleEntry() {
    if (_entry != null) {
      _removeEntry();
      return;
    }

    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeEntry,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.bottomRight,
              offset: const Offset(0, -4),
              child: _LogSettingsPopup(
                controller: widget.controller,
                onClose: _removeEntry,
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }
}

class _LogSettingsPopup extends StatelessWidget {
  const _LogSettingsPopup({
    required this.controller,
    required this.onClose,
  });

  final SessionController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewportSize = MediaQuery.sizeOf(context);
    final availableWidth = math.max(0.0, viewportSize.width - 24);
    final availableHeight = math.max(0.0, viewportSize.height - 24);
    final popupWidth = math.min(340.0, availableWidth);
    final popupMaxHeight = math.min(420.0, availableHeight);
    return Material(
      color: scheme.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: popupWidth,
          maxHeight: popupMaxHeight,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('日志设置', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ViewModeSelector(controller: controller),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('日志文字大小')),
                  IconButton.outlined(
                    tooltip: '减小日志字号',
                    onPressed: controller.decreaseLogFontSize,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 44,
                    child: AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => Text(
                        controller.logFontSize.toStringAsFixed(0),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: '增大日志字号',
                    onPressed: controller.increaseLogFontSize,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return Column(
                    children: [
                      SwitchListTile(
                        value: controller.showTimestamp,
                        onChanged: controller.setTimestampVisible,
                        title: const Text('显示时间戳'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        value: controller.autoScroll,
                        onChanged: controller.setAutoScroll,
                        title: const Text('自动滚动'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: controller.exportLog,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('导出为txt'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewModeSelector extends StatelessWidget {
  const _ViewModeSelector({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          children: [
            const SizedBox(width: 76, child: Text('视图格式')),
            for (final mode in ConsoleViewMode.values) ...[
              Expanded(
                child: _ViewModeButton(
                  mode: mode,
                  selected: controller.viewMode == mode,
                  onPressed: () => controller.setViewMode(mode),
                ),
              ),
              if (mode != ConsoleViewMode.values.last) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.mode,
    required this.selected,
    required this.onPressed,
  });

  final ConsoleViewMode mode;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: selected ? null : onPressed,
      style: OutlinedButton.styleFrom(
        disabledBackgroundColor: scheme.primaryContainer,
        disabledForegroundColor: scheme.onPrimaryContainer,
      ),
      child: Text(mode.label),
    );
  }
}
