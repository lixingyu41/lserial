import 'app_update_models.dart';

AppUpdateService createAppUpdateService() => const _UnsupportedUpdateService();

class _UnsupportedUpdateService implements AppUpdateService {
  const _UnsupportedUpdateService();

  @override
  bool get supported => false;

  @override
  Future<AppUpdateCheckResult> checkForUpdate() {
    throw UnsupportedError('Automatic updates are not supported.');
  }

  @override
  Future<void> downloadAndScheduleInstall(
    AppUpdateRelease release, {
    required void Function(double progress) onProgress,
  }) {
    throw UnsupportedError('Automatic updates are not supported.');
  }
}
