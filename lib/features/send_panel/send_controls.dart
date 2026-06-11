import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../application/workspace_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../widgets/wheel_stepper.dart';

InputDecoration _compactDecoration(String label) {
  return InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    constraints: const BoxConstraints.tightFor(height: 40),
  );
}

InputDecoration _defaultDecoration(String label) {
  return InputDecoration(labelText: label);
}

class SendTargetField extends StatelessWidget {
  const SendTargetField({
    super.key,
    required this.controller,
    required this.width,
    this.compact = false,
  });

  final WorkspaceController controller;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final connectedIndexes = controller.connectedSessionIndexes;
    final selectedValue = connectedIndexes.contains(controller.sendTargetIndex)
        ? controller.sendTargetIndex
        : null;
    return SizedBox(
      width: width,
      child: WheelStepper(
        enabled: connectedIndexes.length > 1,
        onStep: controller.stepSendTarget,
        child: DropdownButtonFormField<int>(
          key: ValueKey(
            'send-target-${controller.sendTargetIndex}-${connectedIndexes.join("|")}',
          ),
          initialValue: selectedValue,
          isExpanded: true,
          decoration: compact
              ? _compactDecoration(controller.strings.sendTo)
              : _defaultDecoration(controller.strings.sendTo),
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
      ),
    );
  }
}

class SendFormatField extends StatelessWidget {
  const SendFormatField({
    super.key,
    required this.controller,
    required this.width,
    this.compact = false,
  });

  final SessionController controller;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<PayloadFormat>(
        key: ValueKey(
          'send-format-${identityHashCode(controller)}-${controller.sendFormat}',
        ),
        initialValue: controller.sendFormat,
        isExpanded: true,
        decoration: compact
            ? _compactDecoration(controller.strings.inputFormat)
            : _defaultDecoration(controller.strings.inputFormat),
        items: PayloadFormat.values
            .map(
              (format) => DropdownMenuItem(
                value: format,
                child: Text(controller.strings.payloadFormat(format)),
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

class SendFormatToggleButton extends StatelessWidget {
  const SendFormatToggleButton({
    super.key,
    required this.controller,
    required this.width,
  });

  final SessionController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: controller.strings.inputFormat,
      child: SizedBox(
        width: width,
        height: 34,
        child: OutlinedButton.icon(
          onPressed: () => controller.setSendFormat(
            controller.sendFormat == PayloadFormat.ascii
                ? PayloadFormat.hex
                : PayloadFormat.ascii,
          ),
          icon: const Icon(Icons.input),
          label: Text(controller.strings.payloadFormat(controller.sendFormat)),
        ),
      ),
    );
  }
}

class LineEndingField extends StatelessWidget {
  const LineEndingField({
    super.key,
    required this.controller,
    required this.width,
    this.compact = false,
  });

  final SessionController controller;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<LineEnding>(
        key: ValueKey(
          'line-ending-${identityHashCode(controller)}-${controller.lineEnding}',
        ),
        initialValue: controller.lineEnding,
        isExpanded: true,
        decoration: compact
            ? _compactDecoration(controller.strings.lineEnding)
            : _defaultDecoration(controller.strings.lineEnding),
        items: LineEnding.values
            .map(
              (ending) => DropdownMenuItem(
                value: ending,
                child: Text(controller.strings.lineEndingLabel(ending)),
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

class ShortcutModeField extends StatelessWidget {
  const ShortcutModeField({
    super.key,
    required this.controller,
    required this.width,
    this.compact = false,
  });

  final SessionController controller;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<SendShortcutMode>(
        key: ValueKey(
          'shortcut-${identityHashCode(controller)}-${controller.sendShortcutMode}',
        ),
        initialValue: controller.sendShortcutMode,
        isExpanded: true,
        decoration: compact
            ? _compactDecoration(controller.strings.sendShortcut)
            : _defaultDecoration(controller.strings.sendShortcut),
        items: SendShortcutMode.values
            .map(
              (mode) => DropdownMenuItem(
                value: mode,
                child: Text(controller.strings.shortcutMode(mode)),
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
