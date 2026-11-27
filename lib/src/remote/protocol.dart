import 'dart:convert';

const remotePort = 43187;
const remoteProtocol = 1;

class RemoteAddress {
  const RemoteAddress(this.host, this.port);
  factory RemoteAddress.parse(String text) {
    final value = text.trim();
    if (value.length > 300 || RegExp(r'[\s\x00-\x1f]').hasMatch(value)) {
      throw const FormatException('Enter an IP address and port.');
    }
    final uri = Uri.tryParse(value.contains('://') ? value : 'broomm://$value');
    if (uri == null ||
        !{'broomm'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Enter an address such as 192.168.1.20:43187.',
      );
    }
    final port = uri.hasPort ? uri.port : remotePort;
    if (port < 1 || port > 65535) throw const FormatException('Invalid port.');
    return RemoteAddress(uri.host.toLowerCase(), port);
  }
  final String host;
  final int port;
  String get label => '${host.contains(':') ? '[$host]' : host}:$port';
  Uri get uri => Uri(scheme: 'broomm', host: host, port: port, path: '/remote');
}

/// SDL positional buttons and signed axes. Trigger values are 0 through 32767.
class RemotePad {
  const RemotePad(this.buttons, this.axes);
  static const neutral = RemotePad(0, [0, 0, 0, 0, 0, 0]);
  factory RemotePad.read(Object? value) {
    if (value is! Map || value['buttons'] is! int || value['axes'] is! List) {
      throw const FormatException('Invalid controller state.');
    }
    final buttons = value['buttons'] as int;
    final axes = (value['axes'] as List).cast<int>();
    if (buttons < 0 ||
        buttons > 0x1fffff ||
        axes.length != 6 ||
        axes.take(4).any((v) => v < -32768 || v > 32767) ||
        axes.skip(4).any((v) => v < 0 || v > 32767)) {
      throw const FormatException('Invalid controller range.');
    }
    return RemotePad(buttons, List.unmodifiable(axes));
  }
  final int buttons;
  final List<int> axes;
  Map<String, Object> get json => {'buttons': buttons, 'axes': axes};
  String get report => '$buttons ${axes.join(' ')}';
}

/// Native touch coordinates and display aspect for the supported second screens.
class RemoteScreenSize {
  const RemoteScreenSize._(
    this.width,
    this.height,
    this.aspectWidth,
    this.aspectHeight,
  );
  static const ds = RemoteScreenSize._(256, 192, 4, 3);
  static const wiiu = RemoteScreenSize._(854, 480, 16, 9);
  final int width, height, aspectWidth, aspectHeight;
  Map<String, int> get json => {'width': width, 'height': height};
  factory RemoteScreenSize.read(Object? value) {
    if (value == null) return ds; // Version-1 peers predate geometry metadata.
    if (value is Map && value['width'] is int && value['height'] is int) {
      for (final size in [ds, wiiu]) {
        if (value['width'] == size.width && value['height'] == size.height)
          return size;
      }
    }
    throw const FormatException('Unsupported remote screen geometry.');
  }
}

/// Coordinates in the negotiated touch screen, independent of video scaling.
class RemoteTouch {
  const RemoteTouch(this.pressed, this.x, this.y);
  static const released = RemoteTouch(false, 0, 0);
  factory RemoteTouch.read(
    Map<String, dynamic> value, {
    RemoteScreenSize size = RemoteScreenSize.ds,
  }) {
    if (value['pressed'] is! bool ||
        value['x'] is! int ||
        value['y'] is! int ||
        (value['x'] as int) < 0 ||
        (value['x'] as int) >= size.width ||
        (value['y'] as int) < 0 ||
        (value['y'] as int) >= size.height) {
      throw const FormatException('Invalid touch coordinates.');
    }
    return RemoteTouch(value['pressed'], value['x'], value['y']);
  }
  final bool pressed;
  final int x, y;
  Map<String, Object> get json => {'pressed': pressed, 'x': x, 'y': y};
  String get report => 'touch ${pressed ? 1 : 0} $x $y';
}

Map<String, dynamic> remoteMessage(Object? value) {
  if (value is! String || value.length > 2048) {
    throw const FormatException('Invalid remote message.');
  }
  final message = jsonDecode(value);
  if (message is! Map<String, dynamic>)
    throw const FormatException('Invalid message.');
  return message;
}
