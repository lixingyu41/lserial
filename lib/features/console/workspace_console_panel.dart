import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/localization.dart';
import '../../application/session_controller.dart';
import '../../application/workspace_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../core/encoding/hex_codec.dart';
import '../../platform/external_link.dart';
import '../../storage/log_buffer.dart';
import '../send_panel/send_controls.dart';
import 'frame_list_view.dart';

class WorkspaceConsolePanel extends StatefulWidget {
  const WorkspaceConsolePanel({
    super.key,
    required this.controller,
    this.panelsStackVertically = false,
  });

  final WorkspaceController controller;
  final bool panelsStackVertically;

  @override
  State<WorkspaceConsolePanel> createState() => _WorkspaceConsolePanelState();
}

class _WorkspaceConsolePanelState extends State<WorkspaceConsolePanel> {
  static const double _terminalInputHeight = 42;

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
                  final terminalMode = widget.controller.terminalMode;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: FrameListView(
                          snapshot: snapshot,
                          formatter: widget.controller.formatter,
                          options: widget.controller.formatOptions,
                          logFontSize: widget.controller.logFontSize,
                          autoScroll: widget.controller.autoScroll,
                          pauseDisplay: widget.controller.pauseDisplay,
                          filter: search.text,
                          visibleSources: widget.controller.visibleSources,
                          bottomPadding:
                              terminalMode ? _terminalInputHeight : 0,
                        ),
                      ),
                      if (terminalMode)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: _terminalInputHeight,
                          child: _TerminalInputLine(
                            controller: widget.controller.sendTarget,
                            logFontSize: widget.controller.logFontSize,
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        _WorkspaceConsoleToolbar(
          controller: widget.controller,
          panelsStackVertically: widget.panelsStackVertically,
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
    required this.panelsStackVertically,
    required this.search,
    required this.onSearchChanged,
  });

  final WorkspaceController controller;
  final bool panelsStackVertically;
  final TextEditingController search;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchAndView = _SearchAndViewMode(
            controller: controller,
            search: search,
            onChanged: onSearchChanged,
          );
          final rightActions = _RightActions(
            controller: controller,
            panelsStackVertically: panelsStackVertically,
          );

          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchAndView,
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
              SizedBox(width: 326, child: searchAndView),
              const SizedBox(width: 8),
              Expanded(child: rightActions),
            ],
          );
        },
      ),
    );
  }
}

class _RightActions extends StatelessWidget {
  const _RightActions({
    required this.controller,
    required this.panelsStackVertically,
  });

  static const double _gap = 8;
  static const double _targetWidth = 190;
  static const double _formatWidth = 96;
  static const double _lineEndingWidth = 96;
  static const double _shortcutWidth = 136;

  final WorkspaceController controller;
  final bool panelsStackVertically;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sendController = controller.sendTarget;
        return Wrap(
          alignment: WrapAlignment.end,
          runAlignment: WrapAlignment.end,
          spacing: _gap,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              height: 34,
              child: OutlinedButton.icon(
                onPressed: controller.clearLog,
                icon: const Icon(Icons.clear_all),
                label: Text(controller.strings.clear),
              ),
            ),
            _TerminalModeButton(controller: controller),
            SendTargetField(
              controller: controller,
              width: _targetWidth,
              compact: true,
            ),
            SendFormatToggleButton(
              controller: sendController,
              width: _formatWidth,
            ),
            LineEndingField(
              controller: sendController,
              width: _lineEndingWidth,
              compact: true,
            ),
            ShortcutModeField(
              controller: sendController,
              width: _shortcutWidth,
              compact: true,
            ),
            _PanelToggleButton(
              tooltip: controller.strings.leftConfigPanel,
              selected: controller.showConnectionPanel,
              icon: panelsStackVertically
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_left,
              onPressed: () => controller.setConnectionPanelVisible(
                !controller.showConnectionPanel,
              ),
            ),
            _PanelToggleButton(
              tooltip: controller.strings.sendData,
              selected: controller.showSendPanel,
              icon: Icons.keyboard,
              onPressed: () => controller.setSendPanelVisible(
                !controller.showSendPanel,
              ),
            ),
            _PanelToggleButton(
              tooltip: controller.strings.quickCommands,
              selected: controller.showQuickCommandsPanel,
              icon: panelsStackVertically
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              onPressed: () => controller.setQuickCommandsPanelVisible(
                !controller.showQuickCommandsPanel,
              ),
            ),
            _LogSettingsButton(controller: controller),
          ],
        );
      },
    );
  }
}

class _TerminalModeButton extends StatelessWidget {
  const _TerminalModeButton({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = controller.terminalMode;
    return SizedBox(
      height: 34,
      child: OutlinedButton.icon(
        onPressed: () => controller.setTerminalMode(!selected),
        icon: const Icon(Icons.terminal),
        label: Text(controller.strings.terminalMode),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? scheme.primaryContainer : null,
          foregroundColor: selected ? scheme.onPrimaryContainer : null,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outline,
          ),
        ),
      ),
    );
  }
}

class _PanelToggleButton extends StatelessWidget {
  const _PanelToggleButton({
    required this.tooltip,
    required this.selected,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool selected;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 34,
      child: IconButton.outlined(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(34),
          fixedSize: const Size.square(34),
          padding: EdgeInsets.zero,
          backgroundColor: selected ? scheme.primaryContainer : null,
          foregroundColor: selected ? scheme.onPrimaryContainer : null,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outline,
          ),
        ),
      ),
    );
  }
}

class _SearchAndViewMode extends StatelessWidget {
  const _SearchAndViewMode({
    required this.controller,
    required this.search,
    required this.onChanged,
  });

  final WorkspaceController controller;
  final TextEditingController search;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SearchField(
            search: search,
            hintText: controller.strings.searchFilter,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        _ViewModeToggleButton(controller: controller),
      ],
    );
  }
}

class _ViewModeToggleButton extends StatelessWidget {
  const _ViewModeToggleButton({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Tooltip(
          message: controller.strings.viewFormat,
          child: SizedBox(
            width: 98,
            height: 34,
            child: OutlinedButton.icon(
              onPressed: () => controller.setViewMode(
                controller.viewMode == ConsoleViewMode.ascii
                    ? ConsoleViewMode.hex
                    : ConsoleViewMode.ascii,
              ),
              icon: const Icon(Icons.visibility),
              label:
                  Text(controller.strings.consoleViewMode(controller.viewMode)),
            ),
          ),
        );
      },
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

class _TerminalInputLine extends StatefulWidget {
  const _TerminalInputLine({
    required this.controller,
    required this.logFontSize,
  });

  final SessionController controller;
  final double logFontSize;

  @override
  State<_TerminalInputLine> createState() => _TerminalInputLineState();
}

class _TerminalInputLineState extends State<_TerminalInputLine> {
  late final TextEditingController input;
  late final FocusNode focusNode;

  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: widget.controller.sendDraftText);
    focusNode = FocusNode(onKeyEvent: _handleSendKey);
    input.addListener(_saveInputDraft);
  }

  @override
  void didUpdateWidget(_TerminalInputLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    input
      ..removeListener(_saveInputDraft)
      ..text = widget.controller.sendDraftText
      ..addListener(_saveInputDraft);
  }

  @override
  void dispose() {
    input.removeListener(_saveInputDraft);
    input.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _saveInputDraft() {
    widget.controller.saveSendDraftText(input.text);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final textStyle = TextStyle(
          fontFamily: 'Consolas',
          fontSize: widget.logFontSize,
          height: 1.35,
          letterSpacing: 0,
          color: scheme.onSurface,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Text(
                '>',
                style: textStyle.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditableText(
                  controller: input,
                  focusNode: focusNode,
                  autofocus: true,
                  maxLines: 1,
                  style: textStyle,
                  cursorColor: scheme.primary,
                  backgroundCursorColor: scheme.onSurfaceVariant,
                  selectionColor: scheme.primary.withValues(alpha: 0.28),
                  keyboardType: TextInputType.text,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  KeyEventResult _handleSendKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      final controlByte = _controlByteFor(event.logicalKey);
      if (controlByte != null) {
        widget.controller.sendRawBytes(<int>[controlByte]);
        return KeyEventResult.handled;
      }
    }

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) {
      return KeyEventResult.ignored;
    }

    _sendLine();
    return KeyEventResult.handled;
  }

  int? _controlByteFor(LogicalKeyboardKey key) {
    return switch (key) {
      LogicalKeyboardKey.keyC => 0x03,
      LogicalKeyboardKey.keyD => 0x04,
      LogicalKeyboardKey.keyZ => 0x1A,
      LogicalKeyboardKey.backslash => 0x1C,
      LogicalKeyboardKey.keyL => 0x0C,
      LogicalKeyboardKey.bracketLeft => 0x1B,
      _ => null,
    };
  }

  void _sendLine() {
    if (!_validateHexInput()) {
      return;
    }
    final text = input.text;
    final shouldClear = widget.controller.isConnected;
    widget.controller.sendText(text);
    if (shouldClear) {
      input.clear();
    }
  }

  bool _validateHexInput() {
    if (widget.controller.sendFormat != PayloadFormat.hex) {
      return true;
    }
    try {
      HexCodec.decode(input.text);
      return true;
    } on FormatException catch (error) {
      final message = switch (error.message) {
        'HEX input must contain an even number of digits.' =>
          widget.controller.strings.hexNeedsEvenDigits,
        _ => widget.controller.strings.hexInvalidChars,
      };
      _showFloatingTip(message);
      return false;
    }
  }

  void _showFloatingTip(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
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
                  const _AppVersionText(),
                  const SizedBox(height: 4),
                  const _SettingsFooterLinks(),
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
            _SettingsFilterChip(
              label: Text(controller.strings.lineEndingSymbols),
              selected: controller.showLineEndingSymbols,
              onSelected: controller.setLineEndingSymbolsVisible,
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

class _AppVersionText extends StatelessWidget {
  const _AppVersionText();

  static final Future<String?> _label = _loadVersionLabel();

  static Future<String?> _loadVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final buildNumber = info.buildNumber.trim();
      if (version.isEmpty) {
        return null;
      }
      return buildNumber.isEmpty ? 'v$version' : 'v$version+$buildNumber';
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _label,
      builder: (context, snapshot) {
        final label = snapshot.data;
        if (label == null || label.isEmpty) {
          return const SizedBox.shrink();
        }
        return Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        );
      },
    );
  }
}

class _SettingsFooterLinks extends StatelessWidget {
  const _SettingsFooterLinks();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _PlatformDownloadLinks(),
        Spacer(),
        _CopyrightLink(),
      ],
    );
  }
}

class _PlatformDownloadLinks extends StatelessWidget {
  const _PlatformDownloadLinks();

  static final Uri _macUrl = Uri.parse(
    'https://github.com/lixingyu41/lserial/releases/download/v1.0.2/LSerial-v1.0.2-macOS.dmg',
  );
  static final Uri _linuxUrl = Uri.parse(
    'https://github.com/lixingyu41/lserial/releases/download/v1.0.2/LSerial-v1.0.2-Linux-x64.tar.gz',
  );
  static final Uri _windowsUrl = Uri.parse(
    'https://github.com/lixingyu41/lserial/releases/download/v1.0.2/LSerial-v1.0.2-Windows-x64-Setup.exe',
  );

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      children: [
        _DownloadIconButton(
          tooltip: 'macOS',
          icon: Icons.laptop_mac,
          url: _macUrl,
        ),
        _DownloadIconButton(
          tooltip: 'Linux',
          icon: Icons.terminal,
          url: _linuxUrl,
        ),
        _DownloadIconButton(
          tooltip: 'Windows',
          icon: Icons.desktop_windows,
          url: _windowsUrl,
        ),
      ],
    );
  }
}

class _DownloadIconButton extends StatelessWidget {
  const _DownloadIconButton({
    required this.tooltip,
    required this.icon,
    required this.url,
  });

  final String tooltip;
  final IconData icon;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: () => _openFooterLink(context, url),
      icon: Icon(icon),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(28),
        fixedSize: const Size.square(28),
        iconSize: 16,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _CopyrightLink extends StatelessWidget {
  const _CopyrightLink();

  static final Uri _url = Uri.parse('https://lixingyu.top');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openFooterLink(context, _url),
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
    );
  }
}

Future<void> _openFooterLink(BuildContext context, Uri url) async {
  try {
    await openExternalLink(url);
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
}
