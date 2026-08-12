import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/session_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../core/encoding/hex_codec.dart';

InputDecoration _framelessSendDecoration(String label) {
  return InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
  );
}

ButtonStyle _framelessSendButtonStyle(BuildContext context) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(40, 40),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    shape: const RoundedRectangleBorder(),
    side: BorderSide.none,
    backgroundColor: Colors.transparent,
    foregroundColor: Theme.of(context).colorScheme.onSurface,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

ButtonStyle _squareFilledButtonStyle() {
  return FilledButton.styleFrom(
    minimumSize: const Size(40, 40),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    shape: const RoundedRectangleBorder(),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class _SendPanelSeparator extends StatelessWidget {
  const _SendPanelSeparator();

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
    widget.controller.addListener(_syncInputDraft);
  }

  @override
  void didUpdateWidget(SendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_syncInputDraft);
    input
      ..removeListener(_saveInputDraft)
      ..text = widget.controller.sendDraftText
      ..addListener(_saveInputDraft);
    interval
      ..removeListener(_saveIntervalDraft)
      ..text = widget.controller.autoSendIntervalText
      ..addListener(_saveIntervalDraft);
    widget.controller.addListener(_syncInputDraft);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncInputDraft);
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

  void _syncInputDraft() {
    final draft = widget.controller.sendDraftText;
    if (input.text == draft) {
      return;
    }
    input.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return LayoutBuilder(
          builder: (context, constraints) {
            final inputHeight = _inputHeightFor(constraints);
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: inputHeight,
                  child: Focus(
                    onKeyEvent: _handleSendKey,
                    child: TextField(
                      key: const ValueKey<String>('send-data-input'),
                      controller: input,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration:
                          _framelessSendDecoration(controller.strings.sendData)
                              .copyWith(alignLabelWithHint: true),
                      onEditingComplete: () {},
                    ),
                  ),
                ),
                const Divider(height: 1),
                _SendActionsRow(
                  controller: controller,
                  interval: interval,
                  onSend: _sendNow,
                  onStart: _startAutoSend,
                ),
              ],
            );
          },
        );
      },
    );
  }

  double _inputHeightFor(BoxConstraints constraints) {
    if (!constraints.maxHeight.isFinite) {
      return 92;
    }
    const reservedHeight = 41.0;
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
        const minInlineWidth = _intervalWidth + _autoSendWidth + _sendMinWidth;
        final sendWidth = math.max(
          _sendMinWidth,
          constraints.maxWidth - _intervalWidth - _autoSendWidth - 2,
        );
        final contentWidth = math.max(constraints.maxWidth, minInlineWidth + 2);

        return ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: contentWidth,
              child: Row(
                children: [
                  _AutoSendIntervalField(
                    controller: controller,
                    interval: interval,
                    width: _intervalWidth,
                  ),
                  const _SendPanelSeparator(),
                  _AutoSendButton(
                    controller: controller,
                    width: _autoSendWidth,
                    onStart: onStart,
                  ),
                  const _SendPanelSeparator(),
                  SizedBox(
                    width: sendWidth,
                    child: _SendButton(
                      label: controller.strings.send,
                      onPressed: onSend,
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

class _SendButton extends StatelessWidget {
  const _SendButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: _squareFilledButtonStyle(),
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
      height: 40,
      child: TextField(
        controller: interval,
        keyboardType: TextInputType.number,
        decoration: _framelessSendDecoration(controller.strings.autoSendMs),
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
      height: 40,
      child: OutlinedButton.icon(
        style: _framelessSendButtonStyle(context),
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
