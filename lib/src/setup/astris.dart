import 'dart:io';

import '../romm/transfer.dart';
import 'archive.dart';

/// Fixed preparation for the reviewed Astris bundle, never imported commands.
/// The managed copy uses Broomm's private preference/bookmark adapter and outer
/// write sandbox; remove only the application-sandbox entitlement which binds
/// the upstream frontend to its system container. Keep the native JIT/HV grants.
Future<void> prepareAstris(Directory bundle) async {
  final file = File('${bundle.parent.path}/astris-entitlements.plist');
  await file.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.cs.allow-dyld-environment-variables</key><true/>
<key>com.apple.security.cs.allow-jit</key><true/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
<key>com.apple.security.cs.debugger</key><true/>
<key>com.apple.security.cs.disable-executable-page-protection</key><true/>
<key>com.apple.security.cs.disable-library-validation</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.get-task-allow</key><true/>
<key>com.apple.security.hypervisor</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
</dict></plist>
''', flush: true);
  await setupTool('/usr/bin/codesign', [
    '--force',
    '--sign',
    '-',
    '--entitlements',
    file.path,
    bundle.path,
  ], DownloadCancellation());
}
