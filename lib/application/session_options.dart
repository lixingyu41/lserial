enum SessionStat {
  rxCount,
  txCount,
  rxCurrentRate,
  txCurrentRate,
  rxRate,
  txRate,
  sessionDuration,
  displayCache,
  droppedData,
  rawCache,
}

const List<SessionStat> sessionStatDisplayOrder = <SessionStat>[
  SessionStat.rxCount,
  SessionStat.txCount,
  SessionStat.rxCurrentRate,
  SessionStat.txCurrentRate,
  SessionStat.rxRate,
  SessionStat.txRate,
  SessionStat.sessionDuration,
  SessionStat.displayCache,
  SessionStat.rawCache,
  SessionStat.droppedData,
];

enum SendShortcutMode {
  enter,
  ctrlEnter,
}
