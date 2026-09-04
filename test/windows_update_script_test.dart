import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/update/app_update_service_io.dart';

void main() {
  test('Windows updater helper is valid PowerShell', () async {
    if (!Platform.isWindows) {
      return;
    }
    final script = buildWindowsUpdateScript(
      processId: 123,
      installerPath: r"C:\Temp\LSerial's update.exe",
      executablePath: r'C:\Program Files\LSerial\lserial.exe',
      installedBuild: true,
    );
    final encoded = base64Encode(utf8.encode(script));
    final result = await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$script = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')); "
          '\$tokens = \$null; \$errors = \$null; '
          '[System.Management.Automation.Language.Parser]::ParseInput('
          '\$script, [ref]\$tokens, [ref]\$errors) | Out-Null; '
          'if (\$errors.Count -gt 0) { \$errors | Out-String | Write-Error; exit 1 }',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(script, contains("LSerial''s update.exe"));
  });
}
