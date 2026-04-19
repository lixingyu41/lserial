import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class WheelStepper extends StatelessWidget {
  const WheelStepper({
    super.key,
    required this.child,
    required this.onStep,
    this.enabled = true,
  });

  final Widget child;
  final ValueChanged<int> onStep;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: enabled ? _handlePointerSignal : null,
      child: child,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) {
      return;
    }
    final step = event.scrollDelta.dy > 0 ? 1 : -1;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => onStep(step),
    );
  }
}
