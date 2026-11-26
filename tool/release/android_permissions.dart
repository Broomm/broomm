/// Check the final merged APK, where variant/library manifests can change the
/// permissions. A maxSdkVersion-limited declaration cannot protect newer hosts.
void verifyAndroidVideoPermissions(String permissionDump) {
  final declared = RegExp(
    r"^uses-permission: name='([^']+)'[ \t]*\r?$",
    multiLine: true,
  ).allMatches(permissionDump).map((m) => m[1]!).toSet();
  final missing = {
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.CHANGE_NETWORK_STATE',
  }.difference(declared);
  if (missing.isNotEmpty) {
    throw StateError(
      'Android APK is missing unrestricted WebRTC network permissions: '
      '${missing.join(', ')}. Refusing to package it.',
    );
  }
}
