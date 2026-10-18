import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_models.dart';
import 'windows_installer_launcher.dart';

const _latestReleaseUri =
    'https://api.github.com/repos/lixingyu41/lserial/releases/latest';

AppUpdateService createAppUpdateService() => _WindowsUpdateService();

class _WindowsUpdateService implements AppUpdateService {
  _WindowsUpdateService();

  String get _executablePath => Platform.resolvedExecutable;

  @override
  bool get supported => Platform.isWindows;

  bool get _isInstalledBuild {
    final executableDirectory = File(_executablePath).parent.path;
    return File(
      '$executableDirectory${Platform.pathSeparator}unins000.exe',
    ).existsSync();
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdate() async {
    if (!supported) {
      throw UnsupportedError('Automatic updates require an installed build.');
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();
    final payload = await _readJson(Uri.parse(_latestReleaseUri));
    return parseAppUpdateRelease(payload, currentVersion: currentVersion);
  }

  @override
  Future<void> downloadAndScheduleInstall(
    AppUpdateRelease release, {
    required void Function(double progress) onProgress,
  }) async {
    if (!supported) {
      throw UnsupportedError('Automatic updates require an installed build.');
    }
    final updateDirectory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}lserial-update',
    );
    await updateDirectory.create(recursive: true);
    final target = File(
      '${updateDirectory.path}${Platform.pathSeparator}${release.fileName}',
    );
    final partial = File('${target.path}.download');
    if (await partial.exists()) {
      await partial.delete();
    }

    final client = HttpClient()..userAgent = 'LSerial updater';
    try {
      final request = await client
          .getUrl(release.downloadUri)
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}.',
          uri: release.downloadUri,
        );
      }
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          sink.add(chunk);
          received += chunk.length;
          onProgress((received / release.fileSize).clamp(0, 1).toDouble());
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received != release.fileSize) {
        throw StateError('Downloaded $received of ${release.fileSize} bytes.');
      }
      final expectedDigest = release.sha256;
      if (expectedDigest != null) {
        final actualDigest = await sha256.bind(partial.openRead()).first;
        if (actualDigest.toString().toLowerCase() != expectedDigest) {
          throw StateError('Downloaded installer checksum does not match.');
        }
      }
      if (await target.exists()) {
        await target.delete();
      }
      await partial.rename(target.path);
      await launchWindowsUpdateInstaller(
        target.path,
        logPath: '${target.path}.install.log',
        installDirectory: _isInstalledBuild
            ? File(_executablePath).parent.path
            : null,
      );
    } finally {
      client.close(force: true);
      if (await partial.exists()) {
        await partial.delete();
      }
    }
  }

  Future<Map<String, Object?>> _readJson(Uri uri) async {
    final client = HttpClient()..userAgent = 'LSerial updater';
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Update check failed with HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('The update response is invalid.');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
