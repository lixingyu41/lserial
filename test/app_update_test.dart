import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/update/app_update_models.dart';

void main() {
  test('app versions compare numeric components', () {
    expect(compareAppVersions('v1.0.20', '1.0.19'), greaterThan(0));
    expect(compareAppVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareAppVersions('1.0.19+20', 'v1.0.19'), 0);
    expect(compareAppVersions('1.0.18', '1.0.19'), lessThan(0));
  });

  test('GitHub release metadata selects and validates Windows installer', () {
    final digest = List<String>.filled(32, 'ab').join();
    final result = parseAppUpdateRelease(<String, Object?>{
      'tag_name': 'v1.0.20',
      'assets': <Object?>[
        <String, Object?>{
          'name': 'LSerial-v1.0.20-Web.zip',
          'size': 10,
          'browser_download_url': 'https://example.com/web.zip',
        },
        <String, Object?>{
          'name': 'LSerial-v1.0.20-Windows-x64-Setup.exe',
          'size': 123,
          'digest': 'sha256:$digest',
          'browser_download_url': 'https://example.com/setup.exe',
        },
      ],
    }, currentVersion: '1.0.19');

    expect(result.updateAvailable, isTrue);
    expect(result.release?.version, '1.0.20');
    expect(result.release?.fileSize, 123);
    expect(result.release?.sha256, digest);
  });

  test('current release does not offer an update', () {
    final result = parseAppUpdateRelease(<String, Object?>{
      'tag_name': 'v1.0.19',
      'assets': <Object?>[],
    }, currentVersion: '1.0.19');

    expect(result.updateAvailable, isFalse);
  });
}
