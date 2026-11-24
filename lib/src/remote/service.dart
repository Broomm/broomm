import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'history.dart';
import '../progress/files.dart';
import 'connection.dart';
import 'protocol.dart';

const remoteActions = {
  'up',
  'down',
  'left',
  'right',
  'accept',
  'back',
  'home',
  'search',
  'options',
  'space',
  'caps',
  'caret-left',
  'caret-right',
  'shift-down',
  'shift-up',
  'keyboard-enter',
};

class RemoteScreenService extends ChangeNotifier with WidgetsBindingObserver {
  RemoteScreenService(
    Directory directory, {
    this.hostEnabled,
    this.onAction,
    this.listenPort = remotePort,
    this.onEvent,
    this.monotonicMillis,
  }) : history = RemoteHistory(directory);
  static const channel = MethodChannel('app.broomm/remote');
  final RemoteHistory history;
  final bool? hostEnabled;
  final int listenPort;
  final void Function(String)? onEvent;
  final int Function()? monotonicMillis;
  final Stopwatch _clock = Stopwatch()..start();
  int get _milliseconds =>
      monotonicMillis?.call() ?? _clock.elapsedMilliseconds;
  final Set<RemoteConnection> _peers = {};
  bool _foreground = true;
  final void Function(String)? onAction;
  ServerSocket? _server;
  RawDatagramSocket? _advertiser, _discovery;
  RemoteConnection? _guest, _client;
  Timer? _heartbeat, _retry, _discoveryTimer;
  Directory? _ipc;
  String? error, discoveryError;
  String status = 'Waiting for a compatible emulator to be launched.';
  List<String> addresses = [];
  final Set<String> discovered = {};
  Uint8List? frame;
  bool connecting = false, _closed = false, _frameBusy = false;
  int _generation = 0, _authCount = 0, _pending = 0;
  DateTime _authWindow = DateTime.now();
  DateTime _lastInput = DateTime.now();
  DateTime _lastHost = DateTime.now();
  int _ticks = 0;
  RemotePad _pad = RemotePad.neutral;
  Object? _sourceDevice;
  bool _padPresent = false;
  RemoteTouch _touch = RemoteTouch.released;
  bool touchSupported = false;
  String? _targetKey;
  Future<void>? _targetWork;
  bool _captureCancelling = false;
  int? _gamePid;
  String? _gameName;
  Map<String, Object>? _target;
  bool get canHost => hostEnabled ?? Platform.isMacOS;
  bool get connected => _client != null;
  bool get hasGuest => _guest != null;
  int? get port => _server?.port;
  String? _inputSocket;
  String? get socketPath => _inputSocket;
  String? newInputSocket() {
    if (_ipc == null) return null;
    _inputSocket = '${_ipc!.path}/p-${progressNonce().substring(0, 12)}';
    return _inputSocket;
  }

  String get clientHost => _clientAddress?.label ?? '';
  RemoteAddress? _clientAddress;

  Future<void>? _startup, _closeWork;
  Future<void>? _discoveryWork;
  Future<void> start() => _startup ??= _start();
  Future<void> _start() async {
    try {
      await history.load();
      if (_closed) return;
      WidgetsBinding.instance.addObserver(this);
      if (canHost) {
        _ipc = await Directory.systemTemp.createTemp('brm-remote-');
        await _startHost();
      }
      if (_closed) return;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'frame' && call.arguments is Uint8List) {
          final bytes = call.arguments as Uint8List;
          if (_guest != null && !_frameBusy && bytes.length <= 1024 * 1024) {
            _frameBusy = true;
            _guest!.add(bytes);
          }
        }
        if (call.method == 'captureError') {
          _sendStatus('Screen capture needs attention. ${call.arguments}');
        }
        if (call.method == 'pad') localPad(call.arguments);
      });
      _heartbeat = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _sendPad();
        if (_touch.pressed) _sendTouch();
        if (_client != null && ++_ticks % 10 == 0) {
          _client!.add(jsonEncode({'type': 'ping'}));
          if (DateTime.now().difference(_lastHost).inSeconds > 5)
            unawaited(_client!.close());
        }
        if (_guest != null &&
            DateTime.now().difference(_lastInput).inMilliseconds > 500) {
          _deliverPad(RemotePad.neutral, false);
          _deliverTouch(RemoteTouch.released);
        }
      });
    } catch (e) {
      error = 'Remote screen could not start. $e';
    }
    _emit();
  }

  Future<void> _startHost() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, listenPort);
      _server!.listen(
        (request) => unawaited(_accept(request)),
        onError: (Object e) {
          error = 'Remote server failed. $e';
          _emit();
        },
      );
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      addresses = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .toList();
      try {
        _advertiser = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _server!.port,
        );
        _advertiser!.listen((event) {
          if (event != RawSocketEvent.read) return;
          final packet = _advertiser?.receive();
          if (packet == null ||
              packet.data.length != 'BROOMM_DISCOVER1'.length ||
              utf8.decode(packet.data, allowMalformed: true) !=
                  'BROOMM_DISCOVER1')
            return;
          final data = utf8.encode(jsonEncode({'broomm': 1, 'port': port}));
          try {
            _advertiser?.send(data, packet.address, packet.port);
          } catch (e) {
            discoveryError =
                'Host discovery is unavailable. Use a manual address.';
            _emit();
          }
        });
      } catch (e) {
        discoveryError = 'Host discovery is unavailable. Use a manual address.';
      }
      error = null;
      onEvent?.call('Remote server listening on port $port');
    } catch (e) {
      error = 'Remote host: $e';
      // A port or network may become available after startup.
      _retry ??= Timer.periodic(const Duration(seconds: 10), (_) {
        if (!_closed && _server == null)
          unawaited(_startHost().then((_) => _emit()));
      });
    }
  }

  Future<void> refreshAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      addresses = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .toList();
      _emit();
    } catch (e) {
      error = 'Could not inspect local network addresses. $e';
      _emit();
    }
  }

  Future<void> _accept(Socket tcp) async {
    if (_closed || _pending >= 4) {
      tcp.destroy();
      return;
    }
    if (DateTime.now().difference(_authWindow).inMinutes >= 1) {
      _authWindow = DateTime.now();
      _authCount = 0;
    }
    if (++_authCount > 30) {
      tcp.destroy();
      return;
    }
    _pending++;
    RemoteConnection? socket;
    Timer? deadline;
    var authenticated = false;
    var senderAnchor = 0, hostAnchor = 0, previousSent = 0;
    try {
      socket = RemoteConnection(tcp);
      _peers.add(socket);
      deadline = Timer(const Duration(seconds: 5), () {
        if (!authenticated) socket?.close(1008, 'Connection code required');
      });
      await for (final data in socket) {
        final message = remoteMessage(data);
        if (!authenticated) {
          if (message['type'] != 'hello' ||
              message['version'] != remoteProtocol ||
              message['sent'] is! int ||
              message['code'] != history.code ||
              _guest != null ||
              _client != null ||
              connecting) {
            await socket.close(
              1008,
              'Check the code, or disconnect the current remote screen.',
            );
            break;
          }
          authenticated = true;
          senderAnchor = previousSent = message['sent'] as int;
          hostAnchor = _milliseconds;
          onEvent?.call('Remote screen connected to this host');
          deadline.cancel();
          _guest = socket;
          _frameBusy = false;
          _lastInput = DateTime.now();
          socket.add(jsonEncode({'type': 'ready', 'version': remoteProtocol}));
          _sendStatus('Waiting for a compatible emulator to be launched.');
          _targetKey = null;
          _syncTarget();
          _emit();
          continue;
        }
        if (message['type'] == 'action' ||
            message['type'] == 'pad' ||
            message['type'] == 'touch') {
          final sent = message['sent'];
          if (sent is! int ||
              sent < previousSent ||
              _milliseconds - hostAnchor - (sent - senderAnchor) > 300 ||
              _milliseconds - hostAnchor - (sent - senderAnchor) < -1000) {
            throw const FormatException(
              'Controller input expired in transit. Reconnect.',
            );
          }
          previousSent = sent;
        }
        switch (message['type']) {
          case 'ping':
            socket.add(jsonEncode({'type': 'pong'}));
          case 'retryCapture':
            _targetKey = null;
            _syncTarget();
          case 'action':
            final action = message['action'];
            if (action is String && remoteActions.contains(action))
              onAction?.call(action);
          case 'pad':
            _lastInput = DateTime.now();
            _deliverPad(RemotePad.read(message), message['connected'] == true);
            if (message['connected'] != true) onAction?.call('shift-up');
          case 'touch':
            final touch = RemoteTouch.read(message);
            if (_gameName == 'melonDS' && _target?['remoteCapture'] != null) {
              _lastInput = DateTime.now();
              _deliverTouch(touch);
            }
          case 'frameAck':
            _frameBusy = false;
            unawaited(channel.invokeMethod<void>('nextFrame'));
          default:
            throw const FormatException('Unsupported remote message.');
        }
      }
    } catch (_) {
      await socket?.close(1002, 'Invalid remote message');
    } finally {
      deadline?.cancel();
      if (socket != null) _peers.remove(socket);
      _pending--;
      if (identical(_guest, socket)) {
        _guest = null;
        onEvent?.call('Remote screen disconnected from this host');
        _frameBusy = false;
        _deliverPad(RemotePad.neutral, false);
        _deliverTouch(RemoteTouch.released);
        onAction?.call('shift-up');
        _targetKey = null;
        _syncTarget();
        _emit();
      }
    }
  }

  void _deliverPad(RemotePad pad, bool present) {
    if (!Platform.isMacOS || socketPath == null) return;
    unawaited(
      channel
          .invokeMethod<void>('input', {
            'path': socketPath,
            'report': '${present ? 1 : 0} ${pad.report}',
          })
          .catchError((Object e) {
            error = 'Remote controller delivery failed. $e';
            _emit();
          }),
    );
  }

  void _deliverTouch(RemoteTouch touch) {
    if (!Platform.isMacOS || socketPath == null) return;
    unawaited(
      channel
          .invokeMethod<void>('input', {
            'path': socketPath,
            'report': touch.report,
          })
          .catchError((Object e) {
            error = 'Remote touch delivery failed. $e';
            _emit();
          }),
    );
  }

  void touch(RemoteTouch value) {
    _touch = touchSupported && _foreground ? value : RemoteTouch.released;
    _sendTouch();
  }

  void _sendTouch() {
    if (touchSupported)
      _client?.add(
        jsonEncode({'type': 'touch', ..._touch.json, 'sent': _milliseconds}),
      );
  }

  void setGame(int? pid, String? name, Map<String, Object>? target) {
    _gamePid = pid;
    _gameName = name;
    _target = target;
    _syncTarget();
  }

  void _syncTarget() {
    if (!Platform.isMacOS || _closed) return;
    final compatible =
        hasGuest &&
        {'melonDS', 'Azahar'}.contains(_gameName) &&
        _gamePid != null &&
        _target != null &&
        (_gameName != 'melonDS' || _target!['remoteCapture'] != null);
    final key = compatible
        ? '$_gamePid:$_gameName:${_target!['seconds']}:${_target!['remoteCapture']}'
        : '';
    if (_targetWork != null) {
      if (_targetKey != key && !_captureCancelling) {
        _captureCancelling = true;
        _targetKey = null;
        unawaited(
          channel.invokeMethod<void>('cancelCapture').catchError((Object _) {}),
        );
      }
      return;
    }
    if (_targetKey == key) return;
    _targetKey = key;
    final args = compatible
        ? <String, Object>{..._target!, 'name': _gameName!}
        : null;
    final work = channel.invokeMethod<void>('capture', args);
    _targetWork = work;
    unawaited(
      work
          .then(
            (_) {
              if (_targetKey != key) return;
              if (compatible)
                _sendStatus('$_gameName secondary screen');
              else
                _sendStatus(
                  'Waiting for a compatible emulator to be launched.',
                );
            },
            onError: (Object e) {
              _sendStatus('Screen capture needs attention. $e');
            },
          )
          .whenComplete(() {
            _targetWork = null;
            _captureCancelling = false;
            _syncTarget();
          }),
    );
  }

  String? _lastStatus;
  void _sendStatus(String value) {
    if (_lastStatus != value) onEvent?.call('Remote screen: $value');
    _lastStatus = value;
    _guest?.add(
      jsonEncode({
        'type': 'status',
        'message': value,
        'touch':
            _gameName == 'melonDS' &&
            _target?['remoteCapture'] != null &&
            value == 'melonDS secondary screen',
      }),
    );
  }

  Future<void> discover() {
    if (_closed) return Future.value();
    return _discoveryWork ??= _discover().whenComplete(
      () => _discoveryWork = null,
    );
  }

  Future<void> _discover() async {
    _discoveryTimer?.cancel();
    _discovery?.close();
    discovered.clear();
    discoveryError = null;
    _emit();
    try {
      final socket = _discovery = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      if (_closed) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket.receive();
        if (packet == null || packet.data.length > 200) return;
        try {
          final message = jsonDecode(utf8.decode(packet.data));
          if (message is Map &&
              message['broomm'] == 1 &&
              message['port'] is int) {
            discovered.add(
              RemoteAddress.parse(
                '${packet.address.address}:${message['port']}',
              ).label,
            );
            _emit();
          }
        } catch (_) {
          /* Ignore unrelated discovery traffic. */
        }
      });
      socket.send(
        utf8.encode('BROOMM_DISCOVER1'),
        InternetAddress('255.255.255.255'),
        remotePort,
      );
      _discoveryTimer = Timer(const Duration(seconds: 3), () {
        socket.close();
        if (identical(_discovery, socket)) _discovery = null;
      });
    } catch (e) {
      _discovery?.close();
      discoveryError =
          'Discovery is unavailable. Enter the host address below. $e';
      _emit();
    }
  }

  Future<void> connect(String address, String code) async {
    if (connecting || connected) return;
    if (_guest != null) {
      error = 'This device already hosts a remote screen. Disconnect that client before connecting to another host.';
      _emit();
      return;
    }
    connecting = true;
    error = null;
    frame = null;
    _emit();
    final generation = ++_generation;
    RemoteConnection? socket;
    try {
      final target = RemoteAddress.parse(address);
      if (canHost &&
          target.port == port &&
          (addresses.contains(target.host) ||
              {'127.0.0.1', 'localhost', '::1'}.contains(target.host))) {
        throw StateError('Choose a Broomm host on another device.');
      }
      socket = RemoteConnection(
        await Socket.connect(
          target.host,
          target.port,
          timeout: const Duration(seconds: 5),
        ),
      );
      if (_closed || generation != _generation) {
        await socket.close();
        return;
      }
      final ready = Completer<void>();
      socket.listen(
        (data) {
          if (generation != _generation || _closed) return;
          try {
            _lastHost = DateTime.now();
            if (data is List<int>) {
              if (!connected || data.length > 1024 * 1024)
                throw const FormatException('Invalid frame.');
              frame = Uint8List.fromList(data);
              _emit();
              return;
            }
            final message = remoteMessage(data);
            if (message['type'] == 'ready' &&
                message['version'] == remoteProtocol &&
                !ready.isCompleted) {
              ready.complete();
            } else if (message['type'] == 'status' &&
                message['message'] is String) {
              touch(RemoteTouch.released);
              touchSupported = message['touch'] == true;
              status = message['message'];
              frame = null;
              _emit();
            }
          } catch (e) {
            socket?.close(1002, 'Invalid host message');
          }
        },
        onError: (Object e) {
          if (!ready.isCompleted) ready.completeError(e);
        },
        onDone: () {
          if (!ready.isCompleted)
            ready.completeError(
              StateError('Connection refused. Check the host code.'),
            );
          if (generation == _generation) {
            _client = null;
            frame = null;
            error = 'Disconnected from the host. Reconnect to continue.';
            _setInput(false);
            _emit();
          }
        },
      );
      socket.add(
        jsonEncode({
          'type': 'hello',
          'version': remoteProtocol,
          'sent': _milliseconds,
          'code': code.trim().toLowerCase(),
        }),
      );
      await ready.future.timeout(const Duration(seconds: 5));
      if (_closed || generation != _generation) {
        await socket.close();
        return;
      }
      _client = socket;
      _lastHost = DateTime.now();
      _clientAddress = target;
      _pad = RemotePad.neutral;
      _padPresent = false;
      _setInput(true);
      await history.remember(target, code.trim().toLowerCase());
    } catch (e) {
      await socket?.close();
      if (generation == _generation) error = 'Could not connect. $e';
    } finally {
      if (generation == _generation) {
        connecting = false;
        _emit();
      }
    }
  }

  void localPad(Object? value) {
    try {
      final device = value is Map ? value['device'] : null;
      if (_sourceDevice != null && device != _sourceDevice) {
        _client?.add(
          jsonEncode({
            'type': 'pad',
            ...RemotePad.neutral.json,
            'connected': false,
            'sent': _milliseconds,
          }),
        );
      }
      _sourceDevice = device;
      _pad = RemotePad.read(value);
      _padPresent = value is Map && value['connected'] == true;
    } catch (_) {
      _pad = RemotePad.neutral;
      _padPresent = false;
    }
    _sendPad();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      touch(RemoteTouch.released);
      _client?.add(
        jsonEncode({
          'type': 'action',
          'action': 'shift-up',
          'sent': _milliseconds,
        }),
      );
      _pad = RemotePad.neutral;
      _padPresent = false;
    }
    _sendPad();
  }

  void _setInput(bool enabled) {
    unawaited(
      channel
          .invokeMethod<void>('controller', enabled)
          .catchError((Object _) {}),
    );
  }

  void action(String action) {
    if (_foreground && remoteActions.contains(action))
      _client?.add(
        jsonEncode({'type': 'action', 'action': action, 'sent': _milliseconds}),
      );
  }

  void _sendPad() {
    _client?.add(
      jsonEncode({
        'type': 'pad',
        ..._pad.json,
        'connected': _padPresent && _foreground,
        'sent': _milliseconds,
      }),
    );
  }

  void retryCapture() => _client?.add(jsonEncode({'type': 'retryCapture'}));
  void frameDisplayed() => _client?.add(jsonEncode({'type': 'frameAck'}));
  Future<void> disconnect() async {
    ++_generation;
    connecting = false;
    touch(RemoteTouch.released);
    touchSupported = false;
    final client = _client;
    _client = null;
    frame = null;
    _setInput(false);
    await client?.close();
    _emit();
  }

  void _emit() {
    if (!_closed) notifyListeners();
  }

  Future<void> close() => _closeWork ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _startup;
    await _discoveryWork;
    WidgetsBinding.instance.removeObserver(this);
    await disconnect();
    _heartbeat?.cancel();
    _retry?.cancel();
    _discoveryTimer?.cancel();
    _advertiser?.close();
    _discovery?.close();
    for (final peer in _peers.toList()) {
      await peer.close();
    }
    await _server?.close();
    if (Platform.isMacOS) {
      try {
        await channel.invokeMethod<void>('capture');
      } on MissingPluginException {
        /* Tests and clients can run without capture. */
      }
    }
    channel.setMethodCallHandler(null);
    // The emulator owns the IPC socket until its writer has stopped.
    if (_gamePid == null && _ipc != null) await _ipc!.delete(recursive: true);
  }
}
