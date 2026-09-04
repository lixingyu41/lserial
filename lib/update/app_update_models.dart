class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.downloadUri,
    required this.fileName,
    required this.fileSize,
    this.sha256,
  });

  final String version;
  final Uri downloadUri;
  final String fileName;
  final int fileSize;
  final String? sha256;
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({required this.currentVersion, this.release});

  final String currentVersion;
  final AppUpdateRelease? release;

  bool get updateAvailable => release != null;
}

abstract interface class AppUpdateService {
  bool get supported;

  Future<AppUpdateCheckResult> checkForUpdate();

  Future<void> downloadAndScheduleInstall(
    AppUpdateRelease release, {
    required void Function(double progress) onProgress,
  });
}

int compareAppVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index++) {
    final leftPart = index < leftParts.length ? leftParts[index] : 0;
    final rightPart = index < rightParts.length ? rightParts[index] : 0;
    final comparison = leftPart.compareTo(rightPart);
    if (comparison != 0) {
      return comparison;
    }
  }
  return 0;
}

AppUpdateCheckResult parseAppUpdateRelease(
  Map<String, Object?> payload, {
  required String currentVersion,
}) {
  final latestVersion = '${payload['tag_name']}'.trim().replaceFirst(
    RegExp(r'^[vV]'),
    '',
  );
  if (!RegExp(r'^\d+(?:\.\d+){1,3}(?:[-+].*)?$').hasMatch(latestVersion)) {
    throw const FormatException('The release version is invalid.');
  }
  if (compareAppVersions(latestVersion, currentVersion) <= 0) {
    return AppUpdateCheckResult(currentVersion: currentVersion);
  }

  final assets = payload['assets'];
  if (assets is! List<Object?>) {
    throw const FormatException('The release does not contain assets.');
  }
  Map<Object?, Object?>? installer;
  for (final asset in assets) {
    if (asset is Map<Object?, Object?> &&
        '${asset['name']}'.endsWith('-Windows-x64-Setup.exe')) {
      installer = asset;
      break;
    }
  }
  if (installer == null) {
    throw const FormatException('Windows installer asset was not found.');
  }
  final downloadUri = Uri.tryParse('${installer['browser_download_url']}');
  final fileName = '${installer['name']}'.trim();
  final fileSize = installer['size'];
  if (downloadUri == null ||
      downloadUri.scheme != 'https' ||
      fileName.isEmpty ||
      fileName.contains('/') ||
      fileName.contains('\\') ||
      fileSize is! int ||
      fileSize <= 0) {
    throw const FormatException('Windows installer metadata is invalid.');
  }
  final digest = installer['digest'];
  String? sha256Value;
  if (digest is String && digest.trim().isNotEmpty) {
    final normalized = digest.trim().toLowerCase();
    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const FormatException('Windows installer checksum is invalid.');
    }
    sha256Value = normalized.substring('sha256:'.length);
  }
  return AppUpdateCheckResult(
    currentVersion: currentVersion,
    release: AppUpdateRelease(
      version: latestVersion,
      downloadUri: downloadUri,
      fileName: fileName,
      fileSize: fileSize,
      sha256: sha256Value,
    ),
  );
}

List<int> _versionParts(String value) {
  final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final core = normalized.split(RegExp(r'[-+]')).first;
  return core
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);
}
