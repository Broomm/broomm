import 'dart:io';

import '../progress/files.dart';
import '../romm/transfer.dart';
import 'archive.dart';

/// Signing recipe for the pinned Dolphin 2609 universal archive. The archive
/// hash is checked before this runs; the entire resulting inventory is checked
/// before installation. Imports cannot provide paths, entitlements or commands.
Future<void> prepareDolphin(Directory bundle) async {
  const files = [
    'Contents/Frameworks/QtCore.framework/Versions/A/QtCore',
    'Contents/Frameworks/QtGui.framework/Versions/A/QtGui',
    'Contents/Frameworks/QtWidgets.framework/Versions/A/QtWidgets',
    'Contents/Frameworks/libMoltenVK.dylib',
    'Contents/Helpers/Dolphin Updater.app/Contents/MacOS/Dolphin Updater',
    'Contents/MacOS/Dolphin',
    'Contents/MacOS/platforms/libqcocoa.dylib',
    'Contents/MacOS/styles/libqmacstyle.dylib',
  ];
  const bundles = [
    'Contents/Frameworks/QtCore.framework',
    'Contents/Frameworks/QtGui.framework',
    'Contents/Frameworks/QtWidgets.framework',
    'Contents/Helpers/Dolphin Updater.app',
  ];
  for (final relative in files) {
    final file = await progressFile(bundle, relative);
    if (!await file.exists())
      throw StateError('The reviewed Dolphin signing component is missing.');
  }
  // Sidecars stay outside the sealed application. These are exactly the
  // original entitlements plus the two flags required for our existing bridge.
  const header = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
''';
  const empty = '$header<dict/>\n</plist>\n';
  const main = '''$header<dict>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
	<key>com.apple.security.cs.allow-dyld-environment-variables</key>
	<true/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
	<key>com.apple.security.device.audio-input</key>
	<true/>
</dict>
</plist>
''';
  final entitlements = File('${bundle.parent.path}/dolphin-entitlements.plist');
  Future<void> sign(String relative, {bool application = false}) async {
    await entitlements.writeAsString(application ? main : empty, flush: true);
    await setupTool('/usr/bin/codesign', [
      '--force',
      '--sign',
      '-',
      '--timestamp=none',
      '--options',
      'runtime',
      '--entitlements',
      entitlements.path,
      relative.isEmpty ? bundle.path : '${bundle.path}/$relative',
    ], DownloadCancellation());
  }

  for (final relative in files) {
    await sign(relative, application: relative == 'Contents/MacOS/Dolphin');
  }
  for (final relative in bundles) {
    await sign(relative);
  }
  await sign('', application: true);
  await setupTool('/usr/bin/codesign', [
    '--verify',
    '--deep',
    '--strict',
    '--all-architectures',
    bundle.path,
  ], DownloadCancellation());
  // Preserve all staging, including the sidecar, if a signing writer's exit is
  // uncertain. The caller owns that failure/recovery boundary.
  await entitlements.delete();
}
