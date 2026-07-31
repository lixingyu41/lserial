import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/session_controller.dart';
import '../../application/workspace_controller.dart';
import '../../application/workspace_settings.dart';
import '../../core/encoding/data_format.dart';
import '../../storage/log_buffer.dart';
import '../send_panel/send_controls.dart';
import 'frame_list_view.dart';

ButtonStyle _toolbarIconStyle(
  ColorScheme scheme, {
  bool selected = false,
}) {
  return IconButton.styleFrom(
    minimumSize: const Size.square(40),
    fixedSize: const Size.square(40),
    padding: EdgeInsets.zero,
    shape: const RoundedRectangleBorder(),
    backgroundColor: selected ? scheme.primaryContainer : null,
    foregroundColor: selected ? scheme.onPrimaryContainer : null,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

ButtonStyle _toolbarTextButtonStyle(ColorScheme scheme) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(40, 40),
    fixedSize: null,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    shape: const RoundedRectangleBorder(),
    side: BorderSide.none,
    backgroundColor: Colors.transparent,
    foregroundColor: scheme.onSurface,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class _ToolbarSeparator extends StatelessWidget {
  const _ToolbarSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      width: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

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

class _WorkspaceConsoleToolbar extends StatefulWidget {
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
  State<_WorkspaceConsoleToolbar> createState() =>
      _WorkspaceConsoleToolbarState();
}

class _WorkspaceConsoleToolbarState extends State<_WorkspaceConsoleToolbar> {
  late final FocusNode _searchFocusNode;
  late bool _searchExpanded;

  @override
  void initState() {
    super.initState();
    _searchExpanded = widget.search.text.isNotEmpty;
    _searchFocusNode = FocusNode()..addListener(_handleSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchFocusNode
      ..removeListener(_handleSearchFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus &&
        widget.search.text.isEmpty &&
        _searchExpanded) {
      setState(() => _searchExpanded = false);
    }
  }

  void _expandSearch() {
    if (!_searchExpanded) {
      setState(() => _searchExpanded = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _handleSearchChanged() {
    if (widget.search.text.isNotEmpty && !_searchExpanded) {
      setState(() => _searchExpanded = true);
    }
    widget.onSearchChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchAndViewWidth = constraints.maxWidth >= 760
              ? 326.0
              : math.max(198.0, math.min(260.0, constraints.maxWidth * 0.42));
          final searchAndView = _SearchAndViewMode(
            controller: widget.controller,
            search: widget.search,
            focusNode: _searchFocusNode,
            expanded: _searchExpanded,
            expandedSearchWidth: searchAndViewWidth - 99,
            onExpand: _expandSearch,
            onChanged: _handleSearchChanged,
          );
          final rightActions = _RightActions(
            controller: widget.controller,
            panelsStackVertically: widget.panelsStackVertically,
          );

          return ClipRect(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        searchAndView,
                        const _ToolbarSeparator(),
                      ],
                    ),
                    rightActions,
                  ],
                ),
              ),
            ),
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

  static const double _targetWidth = 190;
  static const double _formatWidth = 86;
  static const double _lineEndingWidth = 64;
  static const double _shortcutWidth = 94;

  final WorkspaceController controller;
  final bool panelsStackVertically;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sendController = controller.sendTarget;
        final terminalMode = controller.terminalMode;
        final connectedIndexes = controller.connectedSessionIndexes;
        final children = <Widget>[const _ToolbarSeparator()];

        void add(Widget child) {
          if (children.length > 1) {
            children.add(const _ToolbarSeparator());
          }
          children.add(child);
        }

        if (controller.isToolbarActionVisible(
          WorkspaceToolbarAction.clearLog,
        )) {
          add(
            SizedBox.square(
              dimension: 40,
              child: IconButton(
                tooltip: controller.strings.clear,
                onPressed: () {
                  controller.clearLog();
                  _TopStatusBubble.show(context, controller.strings.clear);
                },
                icon: const Icon(Icons.close),
                style: _toolbarIconStyle(Theme.of(context).colorScheme),
              ),
            ),
          );
        }
        if (controller.isToolbarActionVisible(
          WorkspaceToolbarAction.autoScroll,
        )) {
          add(
            _PanelToggleButton(
              tooltip: controller.strings.autoScroll,
              selected: controller.autoScroll,
              icon: Icons.vertical_align_bottom,
              onPressed: () {
                final next = !controller.autoScroll;
                controller.setAutoScroll(next);
                _TopStatusBubble.show(
                  context,
                  controller.strings.settingChanged(
                    controller.strings.autoScroll,
                    controller.strings.onOff(next),
                  ),
                );
              },
            ),
          );
        }
        if (controller.isToolbarActionVisible(
          WorkspaceToolbarAction.terminalMode,
        )) {
          add(_TerminalModeButton(controller: controller));
        }
        if (connectedIndexes.length > 1) {
          add(
            SendTargetField(
              controller: controller,
              width: _targetWidth,
              compact: true,
              frameless: true,
              onChanged: (index) => _TopStatusBubble.show(
                context,
                controller.strings.settingChanged(
                  controller.strings.sendTo,
                  controller.sessionLabel(index),
                ),
              ),
            ),
          );
        }
        if (!terminalMode &&
            controller.isToolbarActionVisible(
              WorkspaceToolbarAction.sendFormat,
            )) {
          add(
            SendFormatToggleButton(
              controller: sendController,
              width: _formatWidth,
              onChanged: (format) => _TopStatusBubble.show(
                context,
                controller.strings.settingChanged(
                  controller.strings.inputFormat,
                  controller.strings.payloadFormat(format),
                ),
              ),
            ),
          );
        }
        if (!terminalMode &&
            controller.isToolbarActionVisible(
              WorkspaceToolbarAction.lineEnding,
            )) {
          add(
            LineEndingToggleButton(
              controller: sendController,
              width: _lineEndingWidth,
              onChanged: (ending) => _TopStatusBubble.show(
                context,
                controller.strings.settingChanged(
                  controller.strings.lineEnding,
                  controller.strings.lineEndingLabel(ending),
                ),
              ),
            ),
          );
        }
        if (!terminalMode &&
            controller.isToolbarActionVisible(
              WorkspaceToolbarAction.sendShortcut,
            )) {
          add(
            ShortcutModeToggleButton(
              controller: sendController,
              width: _shortcutWidth,
              onChanged: (mode) => _TopStatusBubble.show(
                context,
                controller.strings.settingChanged(
                  controller.strings.sendShortcut,
                  controller.strings.shortcutMode(mode),
                ),
              ),
            ),
          );
        }
        if (controller.isToolbarActionVisible(
          WorkspaceToolbarAction.connectionPanel,
        )) {
          add(
            _PanelToggleButton(
              tooltip: controller.strings.leftConfigPanel,
              selected: controller.showConnectionPanel,
              icon: panelsStackVertically
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_left,
              onPressed: () {
                final next = !controller.showConnectionPanel;
                controller.setConnectionPanelVisible(next);
                _TopStatusBubble.show(
                  context,
                  controller.strings.settingChanged(
                    controller.strings.leftConfigPanel,
                    controller.strings.onOff(next),
                  ),
                );
              },
            ),
          );
        }
        if (controller.isToolbarActionVisible(
          WorkspaceToolbarAction.quickCommandsPanel,
        )) {
          add(
            _PanelToggleButton(
              tooltip: controller.strings.quickCommands,
              selected: controller.showQuickCommandsPanel,
              icon: panelsStackVertically
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              onPressed: () {
                final next = !controller.showQuickCommandsPanel;
                controller.setQuickCommandsPanelVisible(next);
                _TopStatusBubble.show(
                  context,
                  controller.strings.settingChanged(
                    controller.strings.quickCommands,
                    controller.strings.onOff(next),
                  ),
                );
              },
            ),
          );
        }
        if (!terminalMode &&
            controller.isToolbarActionVisible(
              WorkspaceToolbarAction.sendPanel,
            )) {
          add(
            _PanelToggleButton(
              tooltip: controller.strings.sendData,
              selected: controller.showSendPanel,
              icon: Icons.keyboard,
              onPressed: () {
                final next = !controller.showSendPanel;
                controller.setSendPanelVisible(next);
                _TopStatusBubble.show(
                  context,
                  controller.strings.settingChanged(
                    controller.strings.sendData,
                    controller.strings.onOff(next),
                  ),
                );
              },
            ),
          );
        }
        add(_LogSettingsButton(controller: controller));

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
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
    return SizedBox.square(
      dimension: 40,
      child: IconButton(
        tooltip: controller.strings.terminalMode,
        onPressed: () {
          final next = !selected;
          controller.setTerminalMode(next);
          _TopStatusBubble.show(
            context,
            controller.strings.settingChanged(
              controller.strings.terminalMode,
              controller.strings.onOff(next),
            ),
          );
        },
        icon: const Icon(Icons.terminal),
        style: _toolbarIconStyle(scheme, selected: selected),
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
      dimension: 40,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style: _toolbarIconStyle(scheme, selected: selected),
      ),
    );
  }
}

class _SearchAndViewMode extends StatelessWidget {
  const _SearchAndViewMode({
    required this.controller,
    required this.search,
    required this.focusNode,
    required this.expanded,
    required this.expandedSearchWidth,
    required this.onExpand,
    required this.onChanged,
  });

  final WorkspaceController controller;
  final TextEditingController search;
  final FocusNode focusNode;
  final bool expanded;
  final double expandedSearchWidth;
  final VoidCallback onExpand;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: expanded ? expandedSearchWidth : 40,
          height: 40,
          child: _SearchField(
            search: search,
            focusNode: focusNode,
            hintText: controller.strings.searchFilter,
            expanded: expanded,
            onExpand: onExpand,
            onChanged: onChanged,
          ),
        ),
        const _ToolbarSeparator(),
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
            height: 40,
            child: OutlinedButton.icon(
              style: _toolbarTextButtonStyle(Theme.of(context).colorScheme),
              onPressed: () {
                final next = controller.viewMode == ConsoleViewMode.ascii
                    ? ConsoleViewMode.hex
                    : ConsoleViewMode.ascii;
                controller.setViewMode(next);
                _TopStatusBubble.show(
                  context,
                  controller.strings.settingChanged(
                    controller.strings.viewFormat,
                    controller.strings.consoleViewMode(next),
                  ),
                );
              },
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
    required this.focusNode,
    required this.hintText,
    required this.expanded,
    required this.onExpand,
    required this.onChanged,
  });

  final TextEditingController search;
  final FocusNode focusNode;
  final String hintText;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return SizedBox.square(
        dimension: 40,
        child: IconButton(
          key: const ValueKey<String>('console-search-toggle'),
          tooltip: hintText,
          onPressed: onExpand,
          icon: const Icon(Icons.search, size: 18),
          style: _toolbarIconStyle(Theme.of(context).colorScheme),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: TextField(
        key: const ValueKey<String>('console-search-field'),
        controller: search,
        focusNode: focusNode,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints:
              const BoxConstraints.tightFor(width: 40, height: 40),
          hintText: hintText,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => onChanged(),
        onTapOutside: (_) => focusNode.unfocus(),
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
    final text = input.text;
    final shouldClear = widget.controller.isConnected;
    widget.controller.sendAsciiText(text);
    if (shouldClear) {
      input.clear();
    }
  }
}

class _TopStatusBubble {
  static OverlayEntry? _entry;

  static void show(BuildContext context, String message) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopStatusBubbleView(
        message: message,
        onDismissed: () {
          if (_entry == entry) {
            _entry = null;
          }
          entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _TopStatusBubbleView extends StatefulWidget {
  const _TopStatusBubbleView({
    required this.message,
    required this.onDismissed,
  });

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_TopStatusBubbleView> createState() => _TopStatusBubbleViewState();
}

class _TopStatusBubbleViewState extends State<_TopStatusBubbleView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 180),
    )..forward();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      _controller.reverse().whenComplete(widget.onDismissed);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 10,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1.4),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: scheme.inverseSurface,
              elevation: 10,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  widget.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onInverseSurface,
                      ),
                ),
              ),
            ),
          ),
        ),
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
        dimension: 40,
        child: IconButton(
          tooltip: widget.controller.strings.logSettings,
          onPressed: _toggleEntry,
          icon: const Icon(Icons.settings),
          style: _toolbarIconStyle(Theme.of(context).colorScheme),
        ),
      ),
    );
  }

  void _toggleEntry() {
    if (_entry != null) {
      _removeEntry();
      _TopStatusBubble.show(
        context,
        widget.controller.strings.settingChanged(
          widget.controller.strings.logSettings,
          widget.controller.strings.onOff(false),
        ),
      );
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
    _TopStatusBubble.show(
      context,
      widget.controller.strings.settingChanged(
        widget.controller.strings.logSettings,
        widget.controller.strings.onOff(true),
      ),
    );
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
                      Semantics(
                        label: strings.close,
                        button: true,
                        child: IconButton(
                          onPressed: onClose,
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Row(
                    children: [
                      Expanded(child: Text(strings.logFontSize)),
                      Semantics(
                        label: strings.decreaseLogFontSize,
                        button: true,
                        child: IconButton(
                          onPressed: controller.decreaseLogFontSize,
                          icon: const Icon(Icons.remove),
                          style: _toolbarIconStyle(scheme),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          controller.logFontSize.toStringAsFixed(0),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Semantics(
                        label: strings.increaseLogFontSize,
                        button: true,
                        child: IconButton(
                          onPressed: controller.increaseLogFontSize,
                          icon: const Icon(Icons.add),
                          style: _toolbarIconStyle(scheme),
                        ),
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
                ],
              ),
            ),
          ),
        );
      },
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
