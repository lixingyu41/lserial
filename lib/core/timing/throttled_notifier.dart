import 'dart:async';

/// Coalesces many updates into one callback per fixed interval.
class ThrottledNotifier {
  ThrottledNotifier({
    required this.interval,
    required this.onTick,
  });

  final Duration interval;
  final void Function() onTick;
  Timer? _timer;
  bool _pending = false;

  void request() {
    _pending = true;
    _timer ??= Timer(interval, _flush);
  }

  void flushNow() {
    _timer?.cancel();
    _timer = null;
    _flush();
  }

  void _flush() {
    _timer = null;
    if (!_pending) {
      return;
    }
    _pending = false;
    onTick();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = false;
  }
}
