enum LogExportResultType {
  saved,
  downloadStarted,
}

class LogExportResult {
  const LogExportResult({
    required this.type,
    required this.target,
  });

  final LogExportResultType type;
  final String target;

  const LogExportResult.saved(String path)
      : this(type: LogExportResultType.saved, target: path);

  const LogExportResult.downloadStarted(String fileName)
      : this(type: LogExportResultType.downloadStarted, target: fileName);
}
