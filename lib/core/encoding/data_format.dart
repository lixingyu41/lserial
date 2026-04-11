enum PayloadFormat {
  ascii,
  hex,
}

enum ConsoleViewMode {
  ascii,
  hex,
}

enum LineEnding {
  none,
  cr,
  lf,
  crlf,
}

extension PayloadFormatLabel on PayloadFormat {
  String get label => switch (this) {
        PayloadFormat.ascii => 'ASCII',
        PayloadFormat.hex => 'HEX',
      };
}

extension ConsoleViewModeLabel on ConsoleViewMode {
  String get label => switch (this) {
        ConsoleViewMode.ascii => 'ASCII',
        ConsoleViewMode.hex => 'HEX',
      };
}

extension LineEndingBytes on LineEnding {
  String get label => switch (this) {
        LineEnding.none => 'None',
        LineEnding.cr => r'CR',
        LineEnding.lf => r'LF',
        LineEnding.crlf => r'CRLF',
      };

  List<int> get bytes => switch (this) {
        LineEnding.none => const <int>[],
        LineEnding.cr => const <int>[13],
        LineEnding.lf => const <int>[10],
        LineEnding.crlf => const <int>[13, 10],
      };
}
