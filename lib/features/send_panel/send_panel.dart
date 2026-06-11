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
  });

  final SessionController controller;

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
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
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
                        decoration: InputDecoration(
                          labelText: controller.strings.sendData,
                          alignLabelWithHint: true,
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                        onEditingComplete: () {},
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SendActionsRow(
                    controller: controller,
                    interval: interval,
                    onSend: _sendNow,
                    onStart: _startAutoSend,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  double _inputHeightFor(BoxConstraints constraints) {
    if (!constraints.maxHeight.isFinite) {
      return 92;
    }
    final actionsWrap = constraints.maxWidth < 390;
    final reservedHeight = actionsWrap ? 96.0 : 56.0;
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

class _SendActionsRow extends StatelessWidget {
  const _SendActionsRow({
    required this.controller,
    required this.interval,
    required this.onSend,
    required this.onStart,
  });

  static const double _gap = 8;
  static const double _intervalWidth = 120;
  static const double _autoSendWidth = 150;
  static const double _sendMinWidth = 96;

  final SessionController controller;
  final TextEditingController interval;
  final VoidCallback onSend;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const inlineMinWidth =
            _intervalWidth + _autoSendWidth + _sendMinWidth + _gap * 2;
        if (constraints.maxWidth >= inlineMinWidth) {
          return Row(
            children: [
              _AutoSendIntervalField(
                controller: controller,
                interval: interval,
                width: _intervalWidth,
              ),
              const SizedBox(width: _gap),
              _AutoSendButton(
                controller: controller,
                width: _autoSendWidth,
                onStart: onStart,
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: _SendButton(
                  label: controller.strings.send,
                  onPressed: onSend,
                ),
              ),
            ],
          );
        }

        const autoControlsWidth = _intervalWidth + _autoSendWidth + _gap;
        final sendFitsAfterAuto =
            constraints.maxWidth >= autoControlsWidth + _gap + _sendMinWidth;
        final sendWidth = sendFitsAfterAuto
            ? constraints.maxWidth - autoControlsWidth - _gap
            : constraints.maxWidth;

        return Wrap(
          spacing: _gap,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _AutoSendIntervalField(
              controller: controller,
              interval: interval,
              width: _intervalWidth,
            ),
            _AutoSendButton(
              controller: controller,
              width: _autoSendWidth,
              onStart: onStart,
            ),
            SizedBox(
              width: sendWidth,
              child: _SendButton(
                label: controller.strings.send,
                onPressed: onSend,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _AutoSendIntervalField extends StatelessWidget {
  const _AutoSendIntervalField({
    required this.controller,
    required this.interval,
    required this.width,
  });

  final SessionController controller;
  final TextEditingController interval;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: interval,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: controller.strings.autoSendMs),
      ),
    );
  }
}

class _AutoSendButton extends StatelessWidget {
  const _AutoSendButton({
    required this.controller,
    required this.width,
    required this.onStart,
  });

  final SessionController controller;
  final double width;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: OutlinedButton.icon(
        onPressed: controller.isAutoSending ? controller.stopAutoSend : onStart,
        icon: Icon(controller.isAutoSending ? Icons.stop : Icons.timer),
        label: Text(
          controller.isAutoSending
              ? controller.strings.stopAutoSend
              : controller.strings.startAutoSend,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
