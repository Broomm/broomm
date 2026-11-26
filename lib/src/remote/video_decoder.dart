import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// One active decode and one replaceable pending JPEG, without ImageCache.
/// The consumer owns each delivered image and disposes it after replacement.
class RemoteFrameDecoder {
  RemoteFrameDecoder({
    required this.onImage,
    this.onDecoded,
    this.onError,
    this.decode = decodeImage,
  });
  final void Function(ui.Image) onImage;
  final void Function(Duration)? onDecoded;
  final void Function()? onError;
  final Future<ui.Image> Function(Uint8List) decode;
  Uint8List? _pending;
  bool _decoding = false, _paused = false, _closed = false;
  int _generation = 0;

  static Future<ui.Image> decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 640,
      targetHeight: 480,
      allowUpscaling: false,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  void add(Uint8List bytes) {
    if (_closed || _paused) return;
    _pending = bytes;
    if (!_decoding) unawaited(_drain());
  }

  void pause(bool value) {
    if (value && !_paused) {
      _generation++;
      _pending = null;
    }
    _paused = value;
  }

  void dispose() {
    _closed = true;
    _pending = null;
  }

  Future<void> _drain() async {
    _decoding = true;
    try {
      while (!_closed && !_paused && _pending != null) {
        final bytes = _pending!, generation = _generation;
        _pending = null;
        final watch = Stopwatch()..start();
        try {
          final image = await decode(bytes);
          if (_closed || _paused || generation != _generation) {
            image.dispose();
            continue;
          }
          onDecoded?.call(watch.elapsed);
          onImage(image);
        } catch (_) {
          if (!_closed && !_paused && generation == _generation)
            onError?.call();
        }
      }
    } finally {
      _decoding = false;
    }
  }
}
