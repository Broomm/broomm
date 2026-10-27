// Run with: devbox run -- flutter test --no-pub tool/render_app_icons.dart
// Render the existing Material infinity mark with the project's pinned Flutter
// renderer. Outputs are checked in; ordinary app builds need no icon tooling.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/progress/digest.dart';

const _mint = Color(0xffbef1e0);

Future<Uint8List> _render(
  int size, {
  bool markOnly = false,
  bool adaptive = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(size / 1024);
  if (!markOnly) {
    final shape = RRect.fromRectAndRadius(
      const Rect.fromLTWH(64, 64, 896, 896),
      const Radius.circular(206),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff26494c), Color(0xff14242f), Color(0xff0b1320)],
          stops: [0, 0.52, 1],
        ).createShader(shape.outerRect),
    );
    canvas.drawRRect(
      shape.deflate(1.5),
      Paint()
        ..color = const Color(0x20ffffff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(Icons.all_inclusive_rounded.codePoint),
      style: TextStyle(
        fontFamily: 'BroommInfinity',
        // 600/1024 of the 108 dp layer stays inside Android's 66 dp safe zone.
        fontSize: adaptive ? 600 : 760,
        height: 1,
        color: _mint,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset((1024 - painter.width) / 2, (1024 - painter.height) / 2),
  );
  painter.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  try {
    if (adaptive) {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final radius = size * 33 / 108;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          if (rgba!.getUint8((y * size + x) * 4 + 3) == 0) continue;
          final dx = x + 0.5 - size / 2, dy = y + 0.5 - size / 2;
          if (dx * dx + dy * dy > radius * radius) {
            throw StateError(
              'Android infinity mark exceeds its 66 dp safe zone.',
            );
          }
        }
      }
    }
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _write(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

Future<void> _windowsIcon() async {
  const sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];
  final frames = [for (final size in sizes) await _render(size)];
  final header = ByteData(6 + 16 * sizes.length)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, sizes.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < sizes.length; i++) {
    final start = 6 + 16 * i;
    header
      ..setUint8(start, sizes[i] == 256 ? 0 : sizes[i])
      ..setUint8(start + 1, sizes[i] == 256 ? 0 : sizes[i])
      ..setUint16(start + 4, 1, Endian.little)
      ..setUint16(start + 6, 32, Endian.little)
      ..setUint32(start + 8, frames[i].length, Endian.little)
      ..setUint32(start + 12, offset, Endian.little);
    offset += frames[i].length;
  }
  await _write('windows/runner/resources/app_icon.ico', [
    ...header.buffer.asUint8List(),
    for (final frame in frames) ...frame,
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render Broomm native application icons', () async {
    final font = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('BroommInfinity')..addFont(Future.value(font))).load();
    final sdkInfo = await Process.run('flutter', [
      '--version',
      '--machine',
    ]).timeout(const Duration(seconds: 30));
    if (sdkInfo.exitCode != 0)
      throw StateError('Cannot locate the pinned Flutter SDK.');
    final sdk = jsonDecode(sdkInfo.stdout as String) as Map;
    final license = File(
      '${sdk['flutterRoot']}/bin/cache/artifacts/material_fonts/MaterialIcons_LICENSE.txt',
    );
    await _write(
      'assets/branding/MATERIAL-ICONS-LICENSE.txt',
      await license.readAsBytes(),
    );
    await _write('assets/branding/broomm-icon.png', await _render(1024));
    await _write(
      'assets/branding/broomm-mark.png',
      await _render(1024, markOnly: true),
    );
    for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
      await _write(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png',
        await _render(size),
      );
    }
    await _windowsIcon();
    await _write('linux/runner/resources/broomm.png', await _render(512));
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    for (final density in densities.entries) {
      final dir = 'android/app/src/main/res/mipmap-${density.key}';
      await _write(
        '$dir/ic_launcher.png',
        await _render((48 * density.value).round()),
      );
      await _write(
        '$dir/ic_launcher_foreground.png',
        await _render(
          (108 * density.value).round(),
          markOnly: true,
          adaptive: true,
        ),
      );
    }
    final digest = ProgressDigest.sha256()
      ..add(font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes));
    stdout.writeln(
      'Rendered macOS, Windows, Linux and Android icons with Flutter ${sdk['frameworkVersion']}; MaterialIcons SHA-256 ${digest.finish()}.',
    );
  });
}
