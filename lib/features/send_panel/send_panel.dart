import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/session_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../core/encoding/hex_codec.dart';

class SendPanel extends StatefulWidget {
  const SendPanel({
    super.key,
    required this.controller,
    this.targetSelector,
  });

  final SessionController controller;
  final Widget? targetSelector;

  @override
  State<SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends State<SendPanel> {
  late final TextEditingController input;
  late final TextEditingController interval;

  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: widget.controller.sendDraftText);
    interval =
        TextEditingController(text: widget.controller.autoSendIntervalText);
    input.addListener(_saveInputDraft);
    interval.addListener(_saveIntervalDraft);
  }

  @override
  void didUpdateWidget(SendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    input
      ..removeListener(_saveInputDraft)
      ..text = widget.controller.sendDraftText
      ..addListener(_saveInputDraft);
    interval
      ..removeListener(_saveIntervalDraft)
      ..text = widget.controller.autoSendIntervalText
      ..addListener(_saveIntervalDraft);
  }

  @override
  void dispose() {
    input.removeListener(_saveInputDraft);
    interval.removeListener(_saveIntervalDraft);
    input.dispose();
    interval.dispose();
    super.dispose();
  }

  void _saveInputDraft() {
    widget.controller.saveSendDraftText(input.text);
  }

  void _saveIntervalDraft() {
    widget.controller.saveAutoSendIntervalText(interval.text);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inputHeight = _inputHeightFor(constraints);
          return ListView(
            children: [
              SizedBox(
                height: inputHeight,
                child: Focus(
                  onKeyEvent: _handleSendKey,
                  child: TextField(
                    controller: input,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: '发送数据',
                      alignLabelWithHint: true,
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    onEditingComplete: () {},
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _SendOptionsRow(
                controller: controller,
                targetSelector: widget.targetSelector,
                onSend: _sendNow,
              ),
              const SizedBox(height: 8),
              _AutoSendRow(
                controller: controller,
                interval: interval,
                onStart: _startAutoSend,
              ),
            ],
          );
        },
      ),
    );
  }

  double _inputHeightFor(BoxConstraints constraints) {
    if (!constraints.maxHeight.isFinite) {
      return 92;
    }
    final optionsWrap = constraints.maxWidth < 700;
    final reservedHeight = optionsWrap ? 178.0 : 118.0;
    return math.max(52, constraints.maxHeight - reservedHeight);
  }

  void _startAutoSend() {
    if (!_validateHexInput()) {
      return;
    }
    final ms = int.tryParse(interval.text) ?? 1000;
    widget.controller.startAutoSend(input.text, Duration(milliseconds: ms));
  }

  KeyEventResult _handleSendKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) {
      return KeyEventResult.ignored;
    }

    final ctrlPressed = HardwareKeyboard.instance.isControlPressed;
    final shouldSend =
        widget.controller.sendShortcutMode == SendShortcutMode.enter
            ? !ctrlPressed
            : ctrlPressed;
    if (shouldSend) {
      _sendNow();
      return KeyEventResult.handled;
    }

    _insertNewline();
    return KeyEventResult.handled;
  }

  void _insertNewline() {
    final value = input.value;
    final text = value.text;
    final start =
        value.selection.start < 0 ? text.length : value.selection.start;
    final end = value.selection.end < 0 ? text.length : value.selection.end;
    final nextText = text.replaceRange(start, end, '\n');
    input.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  void _sendNow() {
    if (!_validateHexInput()) {
      return;
    }
    widget.controller.sendText(input.text);
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
          'HEX 内容需要偶数个十六进制字符',
        _ => 'HEX 内容包含非法字符',
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

class _SendOptionsRow extends StatelessWidget {
  const _SendOptionsRow({
    required this.controller,
    required this.targetSelector,
    required this.onSend,
  });

  final SessionController controller;
  final Widget? targetSelector;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = SizedBox(width: 8);
        final children = [
          if (targetSelector != null) ...[
            SizedBox(width: 190, child: targetSelector!),
            gap,
          ],
          _FormatField(controller: controller),
          gap,
          _LineEndingField(controller: controller),
          gap,
          _ShortcutModeField(controller: controller),
          gap,
          Expanded(
            child: FilledButton(
              onPressed: onSend,
              child: const Text('发送'),
            ),
          ),
        ];

        if (constraints.maxWidth >= 700) {
          return Row(children: children);
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (targetSelector != null)
              SizedBox(width: constraints.maxWidth, child: targetSelector!),
            _FormatField(controller: controller),
            _LineEndingField(controller: controller),
            _ShortcutModeField(controller: controller),
            SizedBox(
              width: constraints.maxWidth,
              child: FilledButton(
                onPressed: onSend,
                child: const Text('发送'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FormatField extends StatelessWidget {
  const _FormatField({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<PayloadFormat>(
        key: ValueKey(
          'send-format-${identityHashCode(controller)}-${controller.sendFormat}',
        ),
        initialValue: controller.sendFormat,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '输入'),
        items: PayloadFormat.values
            .map(
              (format) => DropdownMenuItem(
                value: format,
                child: Text(format.label),
              ),
            )
            .toList(),
        onChanged: (format) {
          if (format != null) {
            controller.setSendFormat(format);
          }
        },
      ),
    );
  }
}

class _LineEndingField extends StatelessWidget {
  const _LineEndingField({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<LineEnding>(
        key: ValueKey(
          'line-ending-${identityHashCode(controller)}-${controller.lineEnding}',
        ),
        initialValue: controller.lineEnding,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '结尾'),
        items: LineEnding.values
            .map(
              (ending) => DropdownMenuItem(
                value: ending,
                child: Text(ending.label),
              ),
            )
            .toList(),
        onChanged: (ending) {
          if (ending != null) {
            controller.setLineEnding(ending);
          }
        },
      ),
    );
  }
}

class _ShortcutModeField extends StatelessWidget {
  const _ShortcutModeField({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<SendShortcutMode>(
        key: ValueKey(
          'shortcut-${identityHashCode(controller)}-${controller.sendShortcutMode}',
        ),
        initialValue: controller.sendShortcutMode,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '发送快捷键'),
        items: SendShortcutMode.values
            .map(
              (mode) => DropdownMenuItem(
                value: mode,
                child: Text(mode.label),
              ),
            )
            .toList(),
        onChanged: (mode) {
          if (mode != null) {
            controller.setSendShortcutMode(mode);
          }
        },
      ),
    );
  }
}

class _AutoSendRow extends StatelessWidget {
  const _AutoSendRow({
    required this.controller,
    required this.interval,
    required this.onStart,
  });

  final SessionController controller;
  final TextEditingController interval;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: TextField(
            controller: interval,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '定时 ms'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                controller.isAutoSending ? controller.stopAutoSend : onStart,
            icon: Icon(controller.isAutoSending ? Icons.stop : Icons.timer),
            label: Text(controller.isAutoSending ? '停止定时' : '定时发送'),
          ),
        ),
      ],
    );
  }
}
