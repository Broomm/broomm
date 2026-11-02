import 'dart:typed_data';

// Original FIPS 197 AES-128 block primitive for bounded media-header inspection.
// This is not an authentication, credential-storage or general encryption API.
int _multiply(int a, int b) {
  var result = 0;
  for (var i = 0; i < 8; i++) {
    if ((b & 1) != 0) result ^= a;
    a = ((a << 1) ^ ((a & 128) != 0 ? 0x11b : 0)) & 255;
    b >>= 1;
  }
  return result;
}

int _power(int value, int exponent) {
  var result = 1;
  while (exponent != 0) {
    if ((exponent & 1) != 0) result = _multiply(result, value);
    value = _multiply(value, value);
    exponent >>= 1;
  }
  return result;
}

final _substitution = List<int>.generate(256, (value) {
  final inverse = value == 0 ? 0 : _power(value, 254);
  var result = inverse ^ 0x63;
  for (var n = 1; n <= 4; n++) {
    result ^= ((inverse << n) | (inverse >> (8 - n))) & 255;
  }
  return result;
}, growable: false);
final _inverseSubstitution = () {
  final result = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) result[_substitution[i]] = i;
  return result;
}();
final _products = {
  for (final factor in [2, 3, 9, 11, 13, 14])
    factor: List<int>.generate(
      256,
      (n) => _multiply(n, factor),
      growable: false,
    ),
};

Uint8List aes128Ecb(Uint8List bytes, Uint8List key, {required bool decrypt}) {
  if (key.length != 16 ||
      bytes.isEmpty ||
      bytes.length % 16 != 0 ||
      bytes.length > 65536) {
    throw const FormatException('Invalid bounded AES input');
  }
  final expanded = Uint8List(176)..setAll(0, key);
  final state = Uint8List(16), shifted = Uint8List(16), word = Uint8List(4);
  final result = Uint8List(bytes.length);
  try {
    var rcon = 1;
    for (var at = 16; at < 176; at += 4) {
      word.setRange(0, 4, expanded, at - 4);
      if (at % 16 == 0) {
        final first = word[0];
        for (var i = 0; i < 3; i++) word[i] = _substitution[word[i + 1]];
        word[3] = _substitution[first];
        word[0] ^= rcon;
        rcon = _products[2]![rcon];
      }
      for (var i = 0; i < 4; i++)
        expanded[at + i] = expanded[at + i - 16] ^ word[i];
    }
    void addKey(int round) {
      for (var i = 0; i < 16; i++) state[i] ^= expanded[round * 16 + i];
    }

    void substituteShift(bool inverse) {
      final table = inverse ? _inverseSubstitution : _substitution;
      for (var column = 0; column < 4; column++) {
        for (var row = 0; row < 4; row++) {
          shifted[column * 4 + row] =
              table[state[((column + (inverse ? -row : row)) & 3) * 4 + row]];
        }
      }
      state.setAll(0, shifted);
    }

    void mix(bool inverse) {
      final factors = inverse ? const [14, 11, 13, 9] : const [2, 3, 1, 1];
      for (var column = 0; column < 16; column += 4) {
        for (var row = 0; row < 4; row++) {
          var value = 0;
          for (var n = 0; n < 4; n++) {
            final factor = factors[(n - row) & 3], input = state[column + n];
            value ^= factor == 1 ? input : _products[factor]![input];
          }
          shifted[column + row] = value;
        }
      }
      state.setAll(0, shifted);
    }

    for (var at = 0; at < bytes.length; at += 16) {
      state.setRange(0, 16, bytes, at);
      addKey(decrypt ? 10 : 0);
      if (decrypt) {
        for (var round = 9; round >= 0; round--) {
          substituteShift(true);
          addKey(round);
          if (round != 0) mix(true);
        }
      } else {
        for (var round = 1; round <= 10; round++) {
          substituteShift(false);
          if (round != 10) mix(false);
          addKey(round);
        }
      }
      result.setRange(at, at + 16, state);
    }
    return result;
  } finally {
    expanded.fillRange(0, expanded.length, 0);
    state.fillRange(0, 16, 0);
    shifted.fillRange(0, 16, 0);
    word.fillRange(0, 4, 0);
  }
}
