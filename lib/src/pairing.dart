enum ControllerTarget {
  snes,
  gamecube,
  wii,
  ps3,
  n3ds,
  nds,
  switchPro,
  pad3do,
  arcade,
  atari,
  jaguar,
  lynx,
  dreamcast,
  gameboy,
  gba,
  n64,
  nes,
  megadrive,
  masterSystem,
  saturn,
  pcengine,
  psx,
  ps2,
  psp;

  bool get isPlayStation =>
      this == psx || this == ps2 || this == ps3 || this == psp;
}

enum WiiMode {
  upright('Upright Remote'),
  classic('Classic Controller'),
  nunchuk('Remote + Nunchuk'),
  sideways('Horizontal Remote');

  const WiiMode(this.label);
  final String label;
}

enum ControllerFamily { unknown, xbox, playstation, nintendo, gamecube }

// Identity belongs to the emulator's SDL runtime, never another enumeration.
class ControllerDevice {
  const ControllerDevice(
    this.id,
    this.name,
    this.buttons,
    this.x,
    this.y, {
    this.rx = 0,
    this.ry = 0,
    this.lt = 0,
    this.rt = 0,
    this.family = ControllerFamily.unknown,
    this.sensors = -1,
    this.sensorReady = 0,
    this.accel = const [0, 0, 0],
    this.gyro = const [0, 0, 0],
  });
  factory ControllerDevice.fromJson(Map<String, dynamic> j) => ControllerDevice(
    j['id'] as int,
    j['name'] as String,
    j['buttons'] as int,
    j['x'] as int,
    j['y'] as int,
    rx: j['rx'] as int? ?? 0,
    ry: j['ry'] as int? ?? 0,
    lt: j['lt'] as int? ?? 0,
    rt: j['rt'] as int? ?? 0,
    family: ControllerFamily.values[j['family'] as int? ?? 0],
    sensors: j['sensors'] as int? ?? -1,
    sensorReady: j['sensorReady'] as int? ?? 0,
    accel: _vector(j['accel']),
    gyro: _vector(j['gyro']),
  );
  static List<double> _vector(dynamic value) {
    if (value is! List || value.length != 3) return const [0, 0, 0];
    return List.unmodifiable(
      value.map((v) {
        if (v is! num || !v.isFinite)
          throw const FormatException('Invalid controller motion sample');
        return v.toDouble();
      }),
    );
  }

  final int id, buttons, x, y, rx, ry, lt, rt;
  final String name;
  final ControllerFamily family;
  // -1 is an older/unknown observation; 0 is confirmed no sensors.
  // Bits 0/1 are accelerometer/gyro. Available and successfully sampled differ.
  final int sensors, sensorReady;
  final List<double> accel, gyro;
  bool get accelerometerAvailable => sensors >= 0 && sensors & 1 != 0;
  bool get gyroAvailable => sensors >= 0 && sensors & 2 != 0;
  bool get accelerometerReady => accelerometerAvailable && sensorReady & 1 != 0;
  bool get gyroReady => gyroAvailable && sensorReady & 2 != 0;
  bool pressed(int button) => buttons & (1 << button) != 0;
  double axis(int index) =>
      ([x, y, rx, ry, lt, rt][index] / 32767).clamp(-1, 1);
  ControllerFamily get inferredFamily {
    if (family != ControllerFamily.unknown) return family;
    final n = name.toLowerCase();
    if (n.contains('gamecube')) return ControllerFamily.gamecube;
    if (n.contains('nintendo') || n.contains('switch') || n.contains('joy-con'))
      return ControllerFamily.nintendo;
    if (n.contains('dual') ||
        n.contains('playstation') ||
        n.contains('ps3') ||
        n.contains('ps4') ||
        n.contains('ps5'))
      return ControllerFamily.playstation;
    if (n.contains('xbox') || n.contains('xinput'))
      return ControllerFamily.xbox;
    return ControllerFamily.unknown;
  }
}

class PlayerAssignment {
  const PlayerAssignment(
    this.deviceId, {
    this.swapFaces = false,
    this.wiiMode = WiiMode.nunchuk,
    this.gyroEnabled = true,
  });
  final int deviceId;
  final bool swapFaces;
  final bool gyroEnabled;
  final WiiMode wiiMode;
  PlayerAssignment toggled() => PlayerAssignment(
    deviceId,
    swapFaces: !swapFaces,
    wiiMode: wiiMode,
    gyroEnabled: gyroEnabled,
  );
  PlayerAssignment withWiiMode(WiiMode mode) => PlayerAssignment(
    deviceId,
    swapFaces: swapFaces,
    wiiMode: mode,
    gyroEnabled: gyroEnabled,
  );
  PlayerAssignment toggledGyro() => PlayerAssignment(
    deviceId,
    swapFaces: swapFaces,
    wiiMode: wiiMode,
    gyroEnabled: !gyroEnabled,
  );
  bool gyroPointer(ControllerDevice? device) =>
      wiiMode != WiiMode.classic &&
      gyroEnabled &&
      device?.gyroAvailable == true &&
      device?.accelerometerAvailable == true;
  bool stickPointer(ControllerDevice? device) =>
      wiiMode != WiiMode.classic && !gyroPointer(device);
  int sourceButton(int logical) =>
      swapFaces && logical < 4 ? logical ^ 1 : logical;
}

class Pairing {
  Pairing(this.capacity, {this.target = ControllerTarget.ps3});
  final int capacity;
  final ControllerTarget target;
  final List<PlayerAssignment> players = [];
  int get visibleSlots => (players.length + 1).clamp(1, capacity);
  bool join(int id, {ControllerDevice? device}) {
    if (players.length == capacity || players.any((p) => p.deviceId == id))
      return false;
    final nintendo = device?.inferredFamily == ControllerFamily.nintendo;
    final diamond = {
      ControllerTarget.snes,
      ControllerTarget.n3ds,
      ControllerTarget.nds,
      ControllerTarget.switchPro,
      ControllerTarget.wii,
      ControllerTarget.gameboy,
      ControllerTarget.gba,
      ControllerTarget.nes,
    }.contains(target);
    players.add(
      PlayerAssignment(id, swapFaces: device != null && (diamond != nintendo)),
    );
    return true;
  }

  void leave(int id) => players.removeWhere((p) => p.deviceId == id);
  void removeDisconnected(Iterable<ControllerDevice> devices) {
    final ids = devices.map((d) => d.id).toSet();
    players.removeWhere((p) => !ids.contains(p.deviceId));
  }

  void toggleLayout(int id) {
    final i = players.indexWhere((p) => p.deviceId == id);
    if (i >= 0) players[i] = players[i].toggled();
  }

  void cycleMode(int id) {
    if (target != ControllerTarget.wii) return;
    final i = players.indexWhere((p) => p.deviceId == id);
    if (i >= 0) {
      final player = players[i];
      players[i] = player.withWiiMode(
        WiiMode.values[(player.wiiMode.index + 1) % WiiMode.values.length],
      );
    }
  }

  void toggleGyro(int id) {
    final i = players.indexWhere((p) => p.deviceId == id);
    if (i >= 0) players[i] = players[i].toggledGyro();
  }

  void setWiiMode(int id, WiiMode mode) {
    final i = players.indexWhere((p) => p.deviceId == id);
    if (i >= 0) players[i] = players[i].withWiiMode(mode);
  }

  void move(int player, int offset) {
    final next = player + offset;
    if (player < 0 || next < 0 || next >= players.length) return;
    players.insert(next, players.removeAt(player));
  }

  bool valid(Iterable<ControllerDevice> devices) {
    final ids = devices.map((d) => d.id).toSet();
    return players.isNotEmpty && players.every((p) => ids.contains(p.deviceId));
  }
}
