import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/workspace_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../storage/log_buffer.dart';
import 'frame_list_view.dart';

class WorkspaceConsolePanel extends StatefulWidget {
  const WorkspaceConsolePanel({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<WorkspaceConsolePanel> createState() => _WorkspaceConsolePanelState();
}

class _WorkspaceConsolePanelState extends State<WorkspaceConsolePanel> {
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
                formatter: widget.controller.formatter,
                options: widget.controller.formatOptions,
                logFontSize: widget.controller.logFontSize,
                autoScroll: widget.controller.autoScroll,
                pauseDisplay: widget.controller.pauseDisplay,
                filter: search.text,
                visibleSources: widget.controller.visibleSources,
              );
            },
          ),
        ),
        const Divider(height: 1),
        _WorkspaceConsoleToolbar(
          controller: widget.controller,
          search: search,
          onSearchChanged: () => setState(() {}),
        ),
      ],
    );
  }
}

class _WorkspaceConsoleToolbar extends StatelessWidget {
  const _WorkspaceConsoleToolbar({
    required this.controller,
    required this.search,
    required this.onSearchChanged,
  });

  final WorkspaceController controller;
  final TextEditingController search;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchField = _SearchField(
            search: search,
            onChanged: onSearchChanged,
          );
          final rightActions = _RightActions(controller: controller);

          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 6),
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

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 34,
          child: OutlinedButton.icon(
            onPressed: controller.clearLog,
            icon: const Icon(Icons.clear_all),
            label: const Text('清空'),
          ),
        ),
        const SizedBox(width: 8),
        _LogSettingsButton(controller: controller),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.search,
    required this.onChanged,
  });

  final TextEditingController search;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: search,
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search, size: 18),
          prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
          hintText: '搜索过滤',
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _LogSettingsButton extends StatefulWidget {
  const _LogSettingsButton({required this.controller});

  final WorkspaceController controller;

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
      child: SizedBox.square(
        dimension: 34,
        child: IconButton.outlined(
          tooltip: '日志设置',
          onPressed: _toggleEntry,
          icon: const Icon(Icons.settings),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(34),
            fixedSize: const Size.square(34),
            padding: EdgeInsets.zero,
          ),
        ),
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

  final WorkspaceController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewportSize = MediaQuery.sizeOf(context);
    final availableWidth = math.max(0.0, viewportSize.width - 24);
    final availableHeight = math.max(0.0, viewportSize.height - 24);
    final popupWidth = math.min(380.0, availableWidth);
    final popupMaxHeight = math.min(520.0, availableHeight);
    return Material(
      color: scheme.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DisplayItems(controller: controller),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        value: controller.autoScroll,
                        onChanged: controller.setAutoScroll,
                        title: const Text('自动滚动'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 6),
                      _SourceFilter(controller: controller),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
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

  final WorkspaceController controller;

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

class _SourceFilter extends StatelessWidget {
  const _SourceFilter({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final labels = controller.sourceLabels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('来源过滤', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final source in labels)
              FilterChip(
                label: Text(source),
                selected: controller.isSourceVisible(source),
                onSelected: (selected) =>
                    controller.setLogSourceVisible(source, selected),
              ),
          ],
        ),
      ],
    );
  }
}

class _DisplayItems extends StatelessWidget {
  const _DisplayItems({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('显示项', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilterChip(
              label: const Text('时间戳'),
              selected: controller.showTimestamp,
              onSelected: controller.setTimestampVisible,
            ),
            FilterChip(
              label: const Text('来源'),
              selected: controller.showSource,
              onSelected: controller.setSourceVisible,
            ),
            FilterChip(
              label: const Text('收发'),
              selected: controller.showDirection,
              onSelected: controller.setDirectionVisible,
            ),
            FilterChip(
              label: const Text('内容'),
              selected: controller.showContent,
              onSelected: controller.setContentVisible,
            ),
          ],
        ),
      ],
    );
  }
}
