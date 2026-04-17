import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/localization.dart';
import '../core/encoding/data_format.dart';
import '../domain/data_frame.dart';
import '../domain/transport.dart';
import '../protocol/frame_formatter.dart';
import '../storage/log_buffer.dart';
import '../storage/log_exporter.dart';
import '../transports/adapters/serial_port_options.dart';
import 'session_controller.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    this.maxCombinedFrames = 30000,
  }) : sessions = <SessionController>[] {
    _addSession(initialize: false);
    _publishSnapshot(force: true);
  }

  final int maxCombinedFrames;
  final List<SessionController> sessions;
  final FrameFormatter formatter = const FrameFormatter();
  final ValueNotifier<LogSnapshot> displaySnapshot =
      ValueNotifier<LogSnapshot>(LogSnapshot.empty());

  int activeSessionIndex = 0;
  int sendTargetIndex = 0;
  ConsoleViewMode viewMode = ConsoleViewMode.ascii;
  bool showTimestamp = true;
  bool showDirection = true;
  bool showSource = true;
  bool showContent = true;
  bool autoScroll = true;
  bool pauseDisplay = false;
  double logFontSize = 12;
  AppLanguage language = AppLanguage.zh;

  final Set<String> _hiddenSources = <String>{};
  int _revision = 0;

  SessionController get activeSession => sessions[activeSessionIndex];

  SessionController get sendTarget => sessions[sendTargetIndex];

  AppStrings get strings => AppStrings.of(language);

  String get windowTitle => activeSession.windowTitle;

  bool get canGoPrevious => activeSessionIndex > 0;

  bool get canGoNext => activeSessionIndex < sessions.length - 1;

  int get connectedSessionCount =>
      sessions.where((session) => session.isConnected).length;

  bool get allSessionsConnected =>
      sessions.isNotEmpty && sessions.every((session) => session.isConnected);

  bool get canAddSession => sessions.length == 1 || allSessionsConnected;

  bool get canRemoveActiveSession =>
      !activeSession.isConnected && sessions.length > 1;

  String get pageIndicator {
    final total = connectedSessionCount;
    if (!activeSession.isConnected) {
      return total == 0
          ? strings.newSession
          : strings.newSessionWithTotal(total);
    }

    var current = 0;
    for (var i = 0; i <= activeSessionIndex; i++) {
      if (sessions[i].isConnected) {
        current++;
      }
    }
    return '$current/$total';
  }

  void setLanguage(AppLanguage next) {
    if (language == next) {
      return;
    }
    language = next;
    for (final session in sessions) {
      session.setLanguage(next);
    }
    notifyListeners();
  }

  ConsoleFormatOptions get formatOptions => ConsoleFormatOptions(
        viewMode: viewMode,
        showTimestamp: showTimestamp,
        showDirection: showDirection,
        showSource: showSource,
        showContent: showContent,
      );

  List<String> get sourceLabels {
    final labels = <String>{'SYS'};
    for (final session in sessions) {
      if (!session.isConnected) {
        continue;
      }
      final label = session.sourceLabel.trim();
      if (label.isNotEmpty) {
        labels.add(label);
      }
    }
    return labels.toList(growable: false);
  }

  Set<String> get visibleSources {
    return sourceLabels
        .where((source) => !_hiddenSources.contains(source))
        .toSet();
  }

  List<int> get connectedSessionIndexes {
    final indexes = <int>[];
    for (var i = 0; i < sessions.length; i++) {
      if (sessions[i].isConnected) {
        indexes.add(i);
      }
    }
    return indexes;
  }

  Future<void> initialize() async {
    await Future.wait(sessions.map((session) => session.initialize()));
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void previousSession() {
    if (!canGoPrevious) {
      return;
    }
    activeSessionIndex--;
    _syncSendTargetIndex();
    notifyListeners();
  }

  void nextSession() {
    if (!canGoNext) {
      return;
    }
    activeSessionIndex++;
    _syncSendTargetIndex();
    notifyListeners();
  }

  Future<void> addSession() async {
    if (!canAddSession) {
      return;
    }
    final session = _addSession(initialize: true);
    activeSessionIndex = sessions.indexOf(session);
    _syncSendTargetIndex();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void removeActiveSession() {
    if (!canRemoveActiveSession) {
      return;
    }
    final removed = sessions.removeAt(activeSessionIndex);
    removed.removeListener(_handleSessionChanged);
    removed.displaySnapshot.removeListener(_handleSessionSnapshotChanged);
    removed.dispose();
    if (activeSessionIndex >= sessions.length) {
      activeSessionIndex = sessions.length - 1;
    }
    if (sendTargetIndex >= sessions.length) {
      sendTargetIndex = activeSessionIndex;
    }
    _syncSendTargetIndex();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setSendTargetIndex(int index) {
    if (index < 0 ||
        index >= sessions.length ||
        !sessions[index].isConnected ||
        index == sendTargetIndex) {
      return;
    }
    sendTargetIndex = index;
    notifyListeners();
  }

  String sessionLabel(int index) {
    return sessions[index].sourceLabel;
  }

  Set<String> occupiedSerialPortsExcept(SessionController current) {
    return sessions
        .where((session) =>
            session != current &&
            session.isConnected &&
            session.config.type == TransportType.serial)
        .map((session) => session.config.serial.portName)
        .where((port) => !isGenericSerialPortName(port))
        .toSet();
  }

  void setViewMode(ConsoleViewMode mode) {
    if (viewMode == mode) {
      return;
    }
    viewMode = mode;
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setTimestampVisible(bool value) {
    if (showTimestamp == value) {
      return;
    }
    showTimestamp = value;
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setSourceVisible(bool value) {
    if (showSource == value) {
      return;
    }
    showSource = value;
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setDirectionVisible(bool value) {
    if (showDirection == value) {
      return;
    }
    showDirection = value;
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setContentVisible(bool value) {
    if (showContent == value) {
      return;
    }
    showContent = value;
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setAutoScroll(bool value) {
    autoScroll = value;
    notifyListeners();
  }

  void setPauseDisplay(bool value) {
    if (pauseDisplay == value) {
      return;
    }
    pauseDisplay = value;
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setLogFontSize(double value) {
    final next = value.clamp(10, 22).toDouble();
    if (next == logFontSize) {
      return;
    }
    logFontSize = next;
    notifyListeners();
  }

  void increaseLogFontSize() => setLogFontSize(logFontSize + 1);

  void decreaseLogFontSize() => setLogFontSize(logFontSize - 1);

  bool isSourceVisible(String source) => !_hiddenSources.contains(source);

  void setLogSourceVisible(String source, bool visible) {
    if (visible) {
      _hiddenSources.remove(source);
    } else {
      _hiddenSources.add(source);
    }
    notifyListeners();
  }

  void toggleLogSource(String source) {
    setLogSourceVisible(source, !isSourceVisible(source));
  }

  void clearLog() {
    for (final session in sessions) {
      session.clearLog();
    }
    _publishSnapshot(force: true);
    notifyListeners();
  }

  Future<void> exportLog() async {
    try {
      final text = displaySnapshot.value.frames
          .where((frame) => visibleSources.contains(_sourceKey(frame)))
          .map((frame) => formatter.formatFrame(frame, formatOptions))
          .join('\n');
      final result = await exportLogText('$text\n');
      activeSession.appendSystemMessage(strings.exportResult(result));
    } on Object catch (error) {
      activeSession.appendSystemMessage(strings.exportFailed(error));
    }
  }

  void _handleSessionChanged() {
    _syncSendTargetIndex();
    notifyListeners();
  }

  void _handleSessionSnapshotChanged() {
    if (!pauseDisplay) {
      _publishSnapshot();
    }
    notifyListeners();
  }

  void _publishSnapshot({bool force = false}) {
    if (pauseDisplay && !force) {
      return;
    }
    _revision++;
    displaySnapshot.value = _buildSnapshot(paused: pauseDisplay);
  }

  LogSnapshot _buildSnapshot({required bool paused}) {
    final frames = <DataFrame>[];
    var totalFrames = 0;
    var totalBytes = 0;
    var droppedFrames = 0;
    var droppedBytes = 0;

    for (final session in sessions) {
      final snapshot = session.logBuffer.snapshot(paused: false);
      frames.addAll(snapshot.frames);
      totalFrames += snapshot.totalFrames;
      totalBytes += snapshot.totalBytes;
      droppedFrames += snapshot.droppedFrames;
      droppedBytes += snapshot.droppedBytes;
    }

    frames.sort((a, b) {
      final time = a.timestamp.compareTo(b.timestamp);
      if (time != 0) {
        return time;
      }
      final source = a.source.compareTo(b.source);
      if (source != 0) {
        return source;
      }
      return a.sequence.compareTo(b.sequence);
    });

    final overflow = frames.length - maxCombinedFrames;
    final visibleFrames = overflow > 0
        ? List<DataFrame>.unmodifiable(frames.sublist(overflow))
        : List<DataFrame>.unmodifiable(frames);

    return LogSnapshot(
      revision: _revision,
      frames: visibleFrames,
      totalFrames: totalFrames,
      totalBytes: totalBytes,
      droppedFrames: droppedFrames + (overflow > 0 ? overflow : 0),
      droppedBytes: droppedBytes,
      paused: paused,
    );
  }

  String _sourceKey(DataFrame frame) {
    return formatter.sourceToken(frame);
  }

  void _syncSendTargetIndex() {
    if (sendTargetIndex >= 0 &&
        sendTargetIndex < sessions.length &&
        sessions[sendTargetIndex].isConnected) {
      return;
    }
    final connectedIndexes = connectedSessionIndexes;
    sendTargetIndex =
        connectedIndexes.isEmpty ? activeSessionIndex : connectedIndexes.first;
  }

  SessionController _addSession({required bool initialize}) {
    final session = SessionController(
      serialAliasNumber: _nextAvailableSerialAliasNumber(),
      language: language,
    );
    session.addListener(_handleSessionChanged);
    session.displaySnapshot.addListener(_handleSessionSnapshotChanged);
    sessions.add(session);
    if (initialize) {
      unawaited(session.initialize());
    }
    return session;
  }

  int _nextAvailableSerialAliasNumber() {
    final usedNumbers = sessions
        .map((session) => session.serialAliasNumber)
        .where((number) => number > 0)
        .toSet();
    var candidate = 1;
    while (usedNumbers.contains(candidate)) {
      candidate++;
    }
    return candidate;
  }

  @override
  void dispose() {
    for (final session in sessions) {
      session.removeListener(_handleSessionChanged);
      session.displaySnapshot.removeListener(_handleSessionSnapshotChanged);
      session.dispose();
    }
    displaySnapshot.dispose();
    super.dispose();
  }
}
