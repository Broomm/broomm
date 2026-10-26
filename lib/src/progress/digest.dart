import 'dart:io';
import 'dart:typed_data';

/// Streaming integrity digests, with SDK-only storage/transport. MD5 is used
/// solely to speak RomM 5.4's content-hash contract, never for authentication.
class ProgressDigest {
  ProgressDigest.sha256()
    : md5 = false,
      _state = Uint32List.fromList([
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
      ]);
  ProgressDigest.md5()
    : md5 = true,
      _state = Uint32List.fromList([
        0x67452301,
        0xefcdab89,
        0x98badcfe,
        0x10325476,
      ]);
  final bool md5;
  final Uint32List _state;
  final _buffer = Uint8List(64);
  int _used = 0, _length = 0;
  bool _closed = false;
  static int _r(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;
  static int _l(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xffffffff;
  void add(List<int> bytes) {
    if (_closed) throw StateError('Digest already finished');
    _length += bytes.length;
    var offset = 0;
    while (offset < bytes.length) {
      final count = (64 - _used).clamp(0, bytes.length - offset);
      _buffer.setRange(_used, _used + count, bytes, offset);
      _used += count;
      offset += count;
      if (_used == 64) {
        _block();
        _used = 0;
      }
    }
  }

  String finish() {
    if (_closed) throw StateError('Digest already finished');
    final bits = _length * 8;
    final padding = Uint8List((_used < 56 ? 64 : 128) - _used);
    padding[0] = 0x80;
    ByteData.sublistView(padding)
        .setUint64(padding.length - 8, bits, md5 ? Endian.little : Endian.big);
    add(padding);
    _closed = true;
    final bytes = ByteData(_state.length * 4);
    for (var i = 0; i < _state.length; i++) {
      bytes.setUint32(i * 4, _state[i], md5 ? Endian.little : Endian.big);
    }
    return bytes.buffer
        .asUint8List()
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void _block() {
    final d = ByteData.sublistView(_buffer);
    if (md5) {
      var a = _state[0], b = _state[1], c = _state[2], e = _state[3];
      for (var i = 0; i < 64; i++) {
        final f = i < 16
            ? (b & c) | (~b & e)
            : i < 32
            ? (e & b) | (~e & c)
            : i < 48
            ? b ^ c ^ e
            : c ^ (b | ~e);
        final g = i < 16
            ? i
            : i < 32
            ? (5 * i + 1) % 16
            : i < 48
            ? (3 * i + 5) % 16
            : (7 * i) % 16;
        final shift = _shifts[(i ~/ 16) * 4 + i % 4];
        final n =
            (b +
                _l(
                  (a + f + _md5K[i] + d.getUint32(g * 4, Endian.little)) &
                      0xffffffff,
                  shift,
                )) &
            0xffffffff;
        a = e;
        e = c;
        c = b;
        b = n;
      }
      final v = [a, b, c, e];
      for (var i = 0; i < 4; i++) {
        _state[i] = (_state[i] + v[i]) & 0xffffffff;
      }
    } else {
      final w = Uint32List(64);
      for (var i = 0; i < 16; i++) {
        w[i] = d.getUint32(i * 4);
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _r(w[i - 15], 7) ^ _r(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _r(w[i - 2], 17) ^ _r(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }
      var a = _state[0],
          b = _state[1],
          c = _state[2],
          e = _state[3],
          f = _state[4],
          g = _state[5],
          h = _state[6],
          j = _state[7];
      for (var i = 0; i < 64; i++) {
        final t1 =
            (j +
                (_r(f, 6) ^ _r(f, 11) ^ _r(f, 25)) +
                ((f & g) ^ (~f & h)) +
                _shaK[i] +
                w[i]) &
            0xffffffff;
        final t2 =
            ((_r(a, 2) ^ _r(a, 13) ^ _r(a, 22)) +
                ((a & b) ^ (a & c) ^ (b & c))) &
            0xffffffff;
        j = h;
        h = g;
        g = f;
        f = (e + t1) & 0xffffffff;
        e = c;
        c = b;
        b = a;
        a = (t1 + t2) & 0xffffffff;
      }
      final v = [a, b, c, e, f, g, h, j];
      for (var i = 0; i < 8; i++) {
        _state[i] = (_state[i] + v[i]) & 0xffffffff;
      }
    }
  }

  static const _shifts = [
    7,
    12,
    17,
    22,
    5,
    9,
    14,
    20,
    4,
    11,
    16,
    23,
    6,
    10,
    15,
    21,
  ];
  static const _md5K = [
    0xd76aa478,
    0xe8c7b756,
    0x242070db,
    0xc1bdceee,
    0xf57c0faf,
    0x4787c62a,
    0xa8304613,
    0xfd469501,
    0x698098d8,
    0x8b44f7af,
    0xffff5bb1,
    0x895cd7be,
    0x6b901122,
    0xfd987193,
    0xa679438e,
    0x49b40821,
    0xf61e2562,
    0xc040b340,
    0x265e5a51,
    0xe9b6c7aa,
    0xd62f105d,
    0x02441453,
    0xd8a1e681,
    0xe7d3fbc8,
    0x21e1cde6,
    0xc33707d6,
    0xf4d50d87,
    0x455a14ed,
    0xa9e3e905,
    0xfcefa3f8,
    0x676f02d9,
    0x8d2a4c8a,
    0xfffa3942,
    0x8771f681,
    0x6d9d6122,
    0xfde5380c,
    0xa4beea44,
    0x4bdecfa9,
    0xf6bb4b60,
    0xbebfbc70,
    0x289b7ec6,
    0xeaa127fa,
    0xd4ef3085,
    0x04881d05,
    0xd9d4d039,
    0xe6db99e5,
    0x1fa27cf8,
    0xc4ac5665,
    0xf4292244,
    0x432aff97,
    0xab9423a7,
    0xfc93a039,
    0x655b59c3,
    0x8f0ccc92,
    0xffeff47d,
    0x85845dd1,
    0x6fa87e4f,
    0xfe2ce6e0,
    0xa3014314,
    0x4e0811a1,
    0xf7537e82,
    0xbd3af235,
    0x2ad7d2bb,
    0xeb86d391,
  ];
  static const _shaK = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
}

class ProgressCrc {
  int _value = 0xffffffff;
  static final _table = List<int>.generate(256, (n) {
    for (var i = 0; i < 8; i++) {
      n = (n & 1) != 0 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
    }
    return n;
  });
  void add(List<int> bytes) {
    for (final b in bytes) {
      _value = _table[(_value ^ b) & 255] ^ (_value >>> 8);
    }
  }

  int get value => (_value ^ 0xffffffff) & 0xffffffff;
}

Future<String> progressFileHash(File file, {bool md5 = false}) async {
  final hash = md5 ? ProgressDigest.md5() : ProgressDigest.sha256();
  await for (final chunk in file.openRead()) {
    hash.add(chunk);
  }
  return hash.finish();
}
