import 'dart:io';

List<String> buildWindowsInstallerArguments({
  required String logPath,
  String? installDirectory,
}) => <String>[
  '/CLOSEAPPLICATIONS',
  '/NORESTART',
  '/LOG=$logPath',
  if (installDirectory != null) '/DIR=$installDirectory',
];

/// Launch the visible installer before allowing the app to close. The detached
/// installer survives the app exiting; CreateProcess failures reach the caller.
Future<void> launchWindowsUpdateInstaller(
  String installerPath, {
  required String logPath,
  String? installDirectory,
}) async {
  await Process.start(
    installerPath,
    buildWindowsInstallerArguments(
      logPath: logPath,
      installDirectory: installDirectory,
    ),
    workingDirectory: File(installerPath).parent.path,
    mode: ProcessStartMode.detached,
  );
}
