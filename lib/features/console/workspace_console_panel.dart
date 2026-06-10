import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/localization.dart';
import '../../application/workspace_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../platform/external_link.dart';
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
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              return ValueListenableBuilder<LogSnapshot>(
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
            hintText: controller.strings.searchFilter,
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
            label: Text(controller.strings.clear),
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
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController search;
  final String hintText;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: search,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 34),
          hintText: hintText,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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
  final GlobalKey _buttonKey = GlobalKey();
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
        key: _buttonKey,
        dimension: 34,
        child: IconButton.outlined(
          tooltip: widget.controller.strings.logSettings,
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
        final viewportSize = MediaQuery.sizeOf(context);
        final popupMaxHeight = _popupMaxHeight(viewportSize);
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
                maxHeight: popupMaxHeight,
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
  }

  double _popupMaxHeight(Size viewportSize) {
    final renderObject = _buttonKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return math.max(0.0, viewportSize.height - 24);
    }
    final targetTop = renderObject.localToGlobal(Offset.zero).dy;
    return math.max(0.0, math.min(520.0, targetTop - 16));
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
    required this.maxHeight,
  });

  final WorkspaceController controller;
  final VoidCallback onClose;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    final availableWidth = math.max(0.0, viewportSize.width - 24);
    final popupWidth = math.min(380.0, availableWidth);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final strings = controller.strings;
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
              maxHeight: maxHeight,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        strings.logSettings,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: strings.close,
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
                      Expanded(child: Text(strings.logFontSize)),
                      IconButton.outlined(
                        tooltip: strings.decreaseLogFontSize,
                        onPressed: controller.decreaseLogFontSize,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          controller.logFontSize.toStringAsFixed(0),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: strings.increaseLogFontSize,
                        onPressed: controller.increaseLogFontSize,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  _DisplayItems(controller: controller),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    value: controller.autoScroll,
                    onChanged: controller.setAutoScroll,
                    title: Text(strings.autoScroll),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: controller.showQuickCommandsPanel,
                    onChanged: controller.setQuickCommandsPanelVisible,
                    title: Text(strings.quickCommands),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: controller.showConnectionPanel,
                    onChanged: controller.setConnectionPanelVisible,
                    title: Text(strings.leftConfigPanel),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 6),
                  _SourceFilter(controller: controller),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: controller.exportLog,
                      icon: const Icon(Icons.save_alt),
                      label: Text(strings.exportTxt),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LanguageSelector(controller: controller),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  const _CopyrightLink(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final strings = controller.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.languageSetting,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final language in AppLanguage.values)
              _SettingsFilterChip(
                label: Text(language.nativeLabel),
                selected: controller.language == language,
                onSelected: (selected) {
                  if (selected) {
                    controller.setLanguage(language);
                  }
                },
              ),
          ],
        ),
      ],
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
            SizedBox(width: 76, child: Text(controller.strings.viewFormat)),
            for (final mode in ConsoleViewMode.values) ...[
              Expanded(
                child: _ViewModeButton(
                  label: controller.strings.consoleViewMode(mode),
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
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
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
      child: Text(label),
    );
  }
}

class _SourceFilter extends StatelessWidget {
  const _SourceFilter({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final labels = controller.sourceLabels;
    final strings = controller.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.sourceFilter,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final source in labels)
              _SettingsFilterChip(
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
        Text(controller.strings.displayItems,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _SettingsFilterChip(
              label: Text(controller.strings.timestamp),
              selected: controller.showTimestamp,
              onSelected: controller.setTimestampVisible,
            ),
            _SettingsFilterChip(
              label: Text(controller.strings.source),
              selected: controller.showSource,
              onSelected: controller.setSourceVisible,
            ),
            _SettingsFilterChip(
              label: Text(controller.strings.direction),
              selected: controller.showDirection,
              onSelected: controller.setDirectionVisible,
            ),
            _SettingsFilterChip(
              label: Text(controller.strings.content),
              selected: controller.showContent,
              onSelected: controller.setContentVisible,
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsFilterChip extends StatelessWidget {
  const _SettingsFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      showCheckmark: false,
      avatar: SizedBox.square(
        dimension: 16,
        child: Icon(
          selected ? Icons.check : Icons.close,
          size: 14,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
      label: label,
      selected: selected,
      onSelected: onSelected,
    );
  }
}

class _CopyrightLink extends StatelessWidget {
  const _CopyrightLink();

  static final Uri _url = Uri.parse('https://lixingyu.top');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.center,
      child: InkWell(
        onTap: () async {
          try {
            await openExternalLink(_url);
          } on Object catch (error) {
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(error.toString()),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            'Copyright LIXINGYU',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: scheme.primary,
                ),
          ),
        ),
      ),
    );
  }
}
