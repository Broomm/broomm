import 'package:flutter_test/flutter_test.dart';

import '../tool/release/android_permissions.dart';

const complete = '''package: app.broomm.broomm
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.CHANGE_NETWORK_STATE'
uses-permission: name='android.permission.REQUEST_INSTALL_PACKAGES'
''';

void main() {
  test('merged APK with WebRTC network permissions can be packaged', () {
    verifyAndroidVideoPermissions(complete);
    verifyAndroidVideoPermissions(complete.replaceAll('\n', '\r\n'));
  });

  test(
    'APK lacking network inspection or callback permissions is rejected',
    () {
      for (final permission in [
        'ACCESS_NETWORK_STATE',
        'CHANGE_NETWORK_STATE',
      ]) {
        final missing = complete
            .split('\n')
            .where((line) => !line.contains('android.permission.$permission'))
            .join('\n');
        expect(
          () => verifyAndroidVideoPermissions(missing),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'missing permission',
              contains(permission),
            ),
          ),
        );
      }
    },
  );

  test('a permission capped to older Android versions does not satisfy the release check', () {
    final capped = complete.replaceFirst(
      "name='android.permission.ACCESS_NETWORK_STATE'",
      "name='android.permission.ACCESS_NETWORK_STATE' maxSdkVersion='32'",
    );
    expect(() => verifyAndroidVideoPermissions(capped), throwsStateError);
    expect(() => verifyAndroidVideoPermissions(''), throwsStateError);
  });
}
