import 'dart:typed_data';
import 'dart:ui' as ui;

import '../romm/client.dart';

/// Check the PNG dimensions before asking Flutter to decode it. The library
/// itself also runs in Dart processes that do not have a Flutter engine.
Future<bool> isDecodablePlatformIcon(Uint8List png) async {
  if (png.length < 33 || png.length > RommClient.platformIconByteLimit) {
    return false;
  }
  final header = ByteData.sublistView(png);
  if (header.getUint32(0) != 0x89504e47 ||
      header.getUint32(4) != 0x0d0a1a0a ||
      header.getUint32(8) != 13 ||
      header.getUint32(12) != 0x49484452) {
    return false;
  }
  final width = header.getUint32(16), height = header.getUint32(20);
  if (width < 1 || height < 1 || width > 256 || height > 256) return false;
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(png);
    if (codec.frameCount != 1) return false;
    final frame = await codec.getNextFrame();
    frame.image.dispose();
    return true;
  } catch (_) {
    return false;
  } finally {
    codec?.dispose();
  }
}
