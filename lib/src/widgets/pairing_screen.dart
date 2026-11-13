import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_model.dart';
import '../pairing.dart';
import '../pairing_gestures.dart';
import 'controller_tester.dart';
import 'motion_tester.dart';
import '../shell/controls.dart';
import '../shell/navigation.dart';

class PairingScreen extends StatelessWidget {
  const PairingScreen({super.key, required this.model});
  final PrototypeModel model;
  @override
  Widget build(BuildContext context) {
    final m = model, pairing = model.pairing!;
    return FocusTraversalGroup(
      policy: ConsoleTraversalPolicy(),
      child: LayoutBuilder(
        builder: (context, viewport) {
          final compact = viewport.maxHeight < 420 || viewport.maxWidth < 500;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Controller pairing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 26 : 38,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -1,
                ),
              ),
              SizedBox(height: compact ? 4 : 8),
              Text(
                m.paused
                    ? 'Press buttons to test your mapping'
                    : 'Waiting for the emulator to pause…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: m.paused ? accent : muted),
              ),
              SizedBox(height: compact ? 14 : 24),
              Expanded(child: _players(pairing)),
              SizedBox(height: compact ? 12 : 18),
              SizedBox(
                height: 20,
                child: Row(
                  children: [
                    Expanded(
                      child: _hold(
                        'Hold Select',
                        m.pairing!.players.fold<double>(
                          0,
                          (v, p) => math.max(
                            v,
                            m.holdProgress(p.deviceId, PairingAction.leave),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _hold(
                        'Hold Start',
                        m.pairing!.players.fold<double>(
                          0,
                          (v, p) => math.max(
                            v,
                            m.holdProgress(p.deviceId, PairingAction.play),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    compact
                        ? 'L1 + R1: join · L3 + R1: swap · L3 + R2: gyro'
                        : pairing.target == ControllerTarget.wii
                        ? 'L1 + R1: join / Wii type · L3 + R1: swap face buttons\nL3 + R2: gyro on/off · Hold Select: remove · Hold Start: play'
                        : 'L1 + R1: join · L3 + R1: swap face buttons\nL3 + R2: gyro on/off · Hold Select: remove · Hold Start: play',
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 11 : 13,
                      height: 1.4,
                      color: Colors.white70,
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ConsoleButton(
                        autofocus: true,
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 12 : 18,
                          vertical: compact ? 8 : 14,
                        ),
                        onPressed: m.busy ? null : () => unawaited(m.stop()),
                        child: const Text('Cancel game'),
                      ),
                      ConsoleButton(
                        fill: const Color(0xff315b54),
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 12 : 22,
                          vertical: compact ? 8 : 16,
                        ),
                        onPressed: m.canPlay ? () => unawaited(m.play()) : null,
                        child: const Text('Apply & play'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
          final width = math.max(280.0, viewport.maxWidth);
          final height = math.max(
            viewport.maxHeight,
            215 * MediaQuery.textScalerOf(context).scale(1),
          );
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(width: width, height: height, child: content),
          );
        },
      ),
    );
  }

  Widget _players(Pairing pairing) => LayoutBuilder(
    builder: (context, constraints) {
      final wii = pairing.target == ControllerTarget.wii;
      final gap = constraints.maxHeight < 320 ? 10.0 : 18.0;
      var columns = 1;
      var bestFit = -1.0;
      var cardSize = Size.zero;
      for (var count = 1; count <= pairing.visibleSlots; count++) {
        final rows = (pairing.visibleSlots + count - 1) ~/ count;
        final width = (constraints.maxWidth - gap * (count - 1)) / count;
        final height = (constraints.maxHeight - gap * (rows - 1)) / rows;
        if (width <= 0 || height <= 0) continue;
        final fit = math.min(width / 440, height / (wii ? 390 : 300));
        if (fit > bestFit) {
          bestFit = fit;
          columns = count;
          cardSize = Size(
            math.min(width, 500),
            math.min(height, wii ? 490 : 400),
          );
        }
      }
      if (cardSize.isEmpty) return const SizedBox.shrink();
      final scale = MediaQuery.textScalerOf(context).scale(1);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: gap,
          children: [
            for (var start = 0; start < pairing.visibleSlots; start += columns)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: gap,
                children: [
                  for (
                    var i = start;
                    i < math.min(start + columns, pairing.visibleSlots);
                    i++
                  )
                    SizedBox.fromSize(
                      size: cardSize,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: math.max(cardSize.width, 285 * scale),
                          height: math.max(
                            cardSize.height,
                            (wii ? 330 : 180) * scale,
                          ),
                          child: _card(context, i, pairing),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );

  Widget _card(BuildContext context, int i, Pairing pairing) {
    final m = model;
    final p = i < pairing.players.length ? pairing.players[i] : null;
    final d = p == null
        ? null
        : m.devices.where((d) => d.id == p.deviceId).firstOrNull;
    final motion = d == null || p == null
        ? null
        : MotionTester(
            device: d,
            target: pairing.target,
            mode: p.wiiMode,
            gyroEnabled: p.gyroEnabled,
          );
    return Container(
      key: ValueKey('player-${i + 1}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p == null
              ? [surface, const Color(0xff101923)]
              : [const Color(0xff203a3b), surface],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: p == null
              ? Colors.white12
              : accent.withValues(alpha: d?.id == m.activeController ? .9 : .5),
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(p?.deviceId),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: p == null
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'PLAYER ${i + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      letterSpacing: 2,
                      color: Colors.white70,
                    ),
                  ),
                ),
                if (p != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _action(
                        'Move player left',
                        Icons.chevron_left,
                        () => m.move(i, -1),
                      ),
                      _action(
                        'Swap face buttons (L3 + R1)',
                        Icons.swap_horiz,
                        () => m.layout(p.deviceId),
                      ),
                      _action(
                        p.gyroEnabled
                            ? 'Gyro on (L3 + R2)'
                            : 'Gyro off (L3 + R2)',
                        p.gyroEnabled
                            ? Icons.screen_rotation
                            : Icons.screen_lock_rotation,
                        () => m.gyro(p.deviceId),
                      ),
                      _action(
                        'Remove controller',
                        Icons.close,
                        () => m.leave(p.deviceId),
                      ),
                      _action(
                        'Move player right',
                        Icons.chevron_right,
                        () => m.move(i, 1),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (p == null) ...[
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Icon(
                    Icons.add_circle_outline,
                    size: 58,
                    color: Colors.white38,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Press L1 + R1 to join',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 3),
              const Text(
                'LB + RB on Xbox · L + R on Nintendo',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              ),
              const SizedBox(height: 6),
              if (m.devices.isEmpty)
                const Text(
                  'Connect a controller by USB or Bluetooth',
                  style: TextStyle(color: Colors.white60),
                ),
              _joinControl(context, pairing),
            ] else ...[
              Text(
                d?.name ?? 'Disconnected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60),
              ),
              if (pairing.target == ControllerTarget.wii)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        p.wiiMode.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff9bdfc0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _action(
                      'Next controller type (L1 + R1)',
                      Icons.autorenew,
                      () => m.cycleMode(p.deviceId),
                    ),
                  ],
                ),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: ControllerTester(
                    target: pairing.target,
                    assignment: p,
                    device: d,
                  ),
                ),
              ),
              if (motion != null) motion,
              if (pairing.target == ControllerTarget.wii)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final mode in WiiMode.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Semantics(
                            selected: p.wiiMode == mode,
                            child: ConsoleButton(
                              onPressed: m.busy
                                  ? null
                                  : () => m.wiiMode(p.deviceId, mode),
                              radius: 10,
                              fill: p.wiiMode == mode
                                  ? const Color(0xff33534f)
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 36,
                                    width: 105,
                                    child: ControllerTester(
                                      target: ControllerTarget.wii,
                                      assignment: p.withWiiMode(mode),
                                      miniature: true,
                                    ),
                                  ),
                                  Text(
                                    mode.label,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _joinControl(BuildContext context, Pairing pairing) {
    final available = model.devices
        .where((d) => !pairing.players.any((p) => p.deviceId == d.id))
        .toList();
    if (available.isEmpty) return const SizedBox.shrink();
    if (available.length == 1) {
      final device = available.single;
      return ConsoleButton(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onPressed: model.canPair ? () => model.join(device.id) : null,
        child: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return ConsoleButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      onPressed: model.canPair
          ? () async {
              final id = await showConsoleDialog<int>(
                context: context,
                builder: (dialogContext) => SimpleDialog(
                  title: const Text('Choose a controller'),
                  children: [
                    for (final device in available)
                      ConsoleButton(
                        autofocus: device == available.first,
                        onPressed: () =>
                            Navigator.pop(dialogContext, device.id),
                        child: Text('${device.name} · #${device.id}'),
                      ),
                    ConsoleButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );
              if (id != null &&
                  context.mounted &&
                  model.canPair &&
                  model.devices.any((d) => d.id == id)) {
                model.join(id);
              }
            }
          : null,
      child: const Text('Choose a controller'),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback action) => Tooltip(
    message: label,
    excludeFromSemantics: true,
    child: SizedBox.square(
      dimension: 32,
      child: ConsoleButton(
        label: label,
        radius: 8,
        padding: EdgeInsets.zero,
        fill: Colors.transparent,
        onPressed: model.busy ? null : action,
        child: Icon(icon, size: 18),
      ),
    ),
  );

  Widget _hold(String label, double progress) => SizedBox(
    height: 20,
    child: Row(
      children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: Colors.white10,
            color: const Color(0xff9bffd6),
          ),
        ),
      ],
    ),
  );
}
