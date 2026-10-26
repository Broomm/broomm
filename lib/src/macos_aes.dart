import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Existing Apple CommonCrypto primitive, isolated from console/file policy.
/// No crypto implementation or third-party runtime is shipped with Broomm.
Uint8List macosAesEcb(Uint8List bytes, Uint8List key, {required bool decrypt}) {
  if (!Platform.isMacOS)
    throw UnsupportedError(
      'This native AES adapter needs its platform implementation.',
    );
  if (key.length != 16 ||
      bytes.isEmpty ||
      bytes.length % 16 != 0 ||
      bytes.length > 65536)
    throw const FormatException('Invalid bounded AES input');
  final system = DynamicLibrary.process();
  final allocate = system
      .lookupFunction<
        Pointer<Uint8> Function(IntPtr, IntPtr),
        Pointer<Uint8> Function(int, int)
      >('calloc');
  final free = system
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  final crypto = DynamicLibrary.open('/usr/lib/system/libcommonCrypto.dylib')
      .lookupFunction<
        Int32 Function(
          Uint32,
          Uint32,
          Uint32,
          Pointer<Void>,
          IntPtr,
          Pointer<Void>,
          Pointer<Void>,
          IntPtr,
          Pointer<Void>,
          IntPtr,
          Pointer<IntPtr>,
        ),
        int Function(
          int,
          int,
          int,
          Pointer<Void>,
          int,
          Pointer<Void>,
          Pointer<Void>,
          int,
          Pointer<Void>,
          int,
          Pointer<IntPtr>,
        )
      >('CCCrypt');
  final memory = allocate(1, 16 + bytes.length * 2 + sizeOf<IntPtr>());
  if (memory == nullptr) throw StateError('Cannot allocate native AES input');
  final moved = (memory + 16 + bytes.length * 2).cast<IntPtr>();
  try {
    memory.asTypedList(16).setAll(0, key);
    (memory + 16).asTypedList(bytes.length).setAll(0, bytes);
    final rc = crypto(
      decrypt ? 1 : 0,
      0,
      2,
      memory.cast(),
      16,
      nullptr,
      (memory + 16).cast(),
      bytes.length,
      (memory + 16 + bytes.length).cast(),
      bytes.length,
      moved,
    );
    if (rc != 0 || moved.value != bytes.length)
      throw StateError('Native AES operation failed');
    return Uint8List.fromList(
      (memory + 16 + bytes.length).asTypedList(bytes.length),
    );
  } finally {
    memory
        .asTypedList(16 + bytes.length * 2 + sizeOf<IntPtr>())
        .fillRange(0, 16 + bytes.length * 2 + sizeOf<IntPtr>(), 0);
    free(memory.cast());
  }
}
