import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/update/windows_installer_launcher.dart';

void main() {
  test(
    'installed update opens the wizard and preserves its install directory',
    () {
      final arguments = buildWindowsInstallerArguments(
        logPath: r"C:\Temp\更新's log.txt",
        installDirectory: r"C:\Users\user\App's folder",
      );
      expect(arguments, <String>[
        '/CLOSEAPPLICATIONS',
        '/NORESTART',
        r"/LOG=C:\Temp\更新's log.txt",
        r"/DIR=C:\Users\user\App's folder",
      ]);
    },
  );

  test('portable update leaves the install directory to the wizard', () {
    final arguments = buildWindowsInstallerArguments(
      logPath: r'C:\Temp\log.txt',
    );
    expect(arguments.any((argument) => argument.startsWith('/DIR=')), isFalse);
  });

  test('installer process creation failure reaches the caller', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lserial-launch-failure-',
    );
    addTearDown(() => directory.delete(recursive: true));
    await expectLater(
      launchWindowsUpdateInstaller(
        '${directory.path}${Platform.pathSeparator}missing-installer.exe',
        logPath: '${directory.path}${Platform.pathSeparator}install.log',
      ),
      throwsA(isA<ProcessException>()),
    );
  });

  test(
    'installer receives literal paths and survives its launcher exiting',
    () async {
      if (!Platform.isWindows) {
        return;
      }
      final directory = await Directory.systemTemp.createTemp(
        "lserial 更新's test-",
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}\\installer.cs');
      final installer = File('${directory.path}\\installer.exe');
      final marker = File('${directory.path}\\arguments.txt');
      final logPath = '${directory.path}\\更新 install.log';
      final installDirectory = '${directory.path}\\程序 App\'s folder';
      await source.writeAsString(r'''
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
class InstallerFixture {
  static void Main(string[] args) {
    int parentId = int.Parse(File.ReadAllText(Path.Combine(
      AppDomain.CurrentDomain.BaseDirectory, "launcher.pid")));
    try {
      using (Process parent = Process.GetProcessById(parentId)) {
        if (!parent.WaitForExit(5000)) return;
      }
    } catch (ArgumentException) {}
    File.WriteAllLines(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
      "arguments.txt"), args, new UTF8Encoding(false));
  }
}
''');
      final compiler =
          '${Platform.environment['WINDIR']}\\Microsoft.NET\\Framework64\\v4.0.30319\\csc.exe';
      final compiled = await Process.run(compiler, <String>[
        '/nologo',
        '/target:winexe',
        '/out:${installer.path}',
        source.path,
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );

      final launcher = File('${directory.path}\\launcher.dart');
      final library = File(
        'lib/update/windows_installer_launcher.dart',
      ).absolute.uri;
      await launcher.writeAsString('''
import 'dart:io';
import ${jsonEncode(library.toString())};
Future<void> main() async {
  await File(${jsonEncode('${directory.path}\\launcher.pid')}).writeAsString(pid.toString());
  await launchWindowsUpdateInstaller(
    ${jsonEncode(installer.path)},
    logPath: ${jsonEncode(logPath)},
    installDirectory: ${jsonEncode(installDirectory)},
  );
}
''');
      final launched = await Process.run('dart', <String>[
        launcher.path,
      ], runInShell: true);
      expect(
        launched.exitCode,
        0,
        reason: '${launched.stdout}\n${launched.stderr}',
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!await marker.exists() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        await marker.exists(),
        isTrue,
        reason: 'Detached installer must continue after the launcher exits.',
      );
      expect(
        await marker.readAsLines(),
        buildWindowsInstallerArguments(
          logPath: logPath,
          installDirectory: installDirectory,
        ),
      );
    },
  );
}
