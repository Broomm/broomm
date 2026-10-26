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

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.model});
  final PrototypeModel model;
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  PrototypeModel get model => widget.model;
  final _cardKeys = <int, GlobalKey>{};
  int? _lastActive;
  @override
  Widget build(BuildContext context) {
    final m = model, pairing = model.pairing!;
    final active = m.activeController;
    if (active != _lastActive) {
      _lastActive = active;
      if (active != null)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = _cardKeys[active]?.currentContext;
          if (mounted && context != null)
            Scrollable.ensureVisible(
              context,
              alignment: .5,
              duration: motionDuration(context),
              curve: consoleCurve,
            );
        });
    }
    return FocusTraversalGroup(
      policy: ConsoleTraversalPolicy(),
      child: LayoutBuilder(
        builder: (context, viewport) {
          final compact = viewport.maxHeight < 420;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Controller pairing',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                m.paused
                    ? 'Ready when you are · Press buttons to test your mapping'
                    : 'Waiting for the emulator to pause…',
                style: TextStyle(color: m.paused ? accent : muted),
              ),
              const SizedBox(height: 16),
              if (compact)
                SizedBox(height: 320, child: _players(pairing))
              else
                Expanded(child: _players(pairing)),
              const SizedBox(height: 6),
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
                    const SizedBox(width: 24),
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
                    pairing.target == ControllerTarget.wii
                        ? 'L1 + R1: join / Wii type · L3 + R1: swap face buttons\nL3 + R2: gyro on/off · Hold Select: remove · Hold Start: play (1 second)'
                        : 'L1 + R1: join · L3 + R1: swap face buttons\nL3 + R2: gyro on/off · Hold Select: remove · Hold Start: play (1 second)',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.8,
                      color: Colors.white70,
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ConsoleButton(
                        autofocus: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        onPressed: m.busy ? null : () => unawaited(m.stop()),
                        child: const Text('Cancel game'),
                      ),
                      ConsoleButton(
                        fill: const Color(0xff315b54),
                        onPressed: m.canPlay ? () => unawaited(m.play()) : null,
                        child: const Text('Apply & play'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
          return compact ? ConsoleScrollView(child: content) : content;
        },
      ),
    );
  }

  Widget _players(Pairing pairing) => LayoutBuilder(
    builder: (context, constraints) => ConsoleScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 18,
            runSpacing: 18,
            children: [
              for (var i = 0; i < pairing.visibleSlots; i++)
                SizedBox(
                  width: math.min(500, constraints.maxWidth),
                  child: _card(context, i, pairing, constraints.maxHeight),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _card(
    BuildContext context,
    int i,
    Pairing pairing,
    double availableHeight,
  ) {
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
      padding: const EdgeInsets.all(20),
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
          color: p == null ? Colors.white12 : accent.withValues(alpha: .5),
        ),
      ),
      child: KeyedSubtree(
        key: p == null
            ? null
            : _cardKeys.putIfAbsent(p.deviceId, () => GlobalKey()),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: p == null
                  ? WrapAlignment.center
                  : WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 6,
              children: [
                Text(
                  'PLAYER ${i + 1}',
                  style: const TextStyle(
                    fontSize: 13,
                    letterSpacing: 2,
                    color: Colors.white70,
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
              const SizedBox(height: 36),
              const Icon(
                Icons.add_circle_outline,
                size: 58,
                color: Colors.white38,
              ),
              const SizedBox(height: 22),
              const Text(
                'Press L1 + R1 to join',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              const Text(
                'LB + RB on Xbox · L + R on Nintendo',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              ),
              const SizedBox(height: 24),
              if (m.devices.isEmpty)
                const Text(
                  'Connect a controller by USB or Bluetooth',
                  style: TextStyle(color: Colors.white60),
                ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in m.devices.where(
                    (d) => !pairing.players.any((p) => p.deviceId == d.id),
                  ))
                    ActionChip(
                      label: Text('${d.name} · #${d.id}'),
                      onPressed: m.canPair ? () => m.join(d.id) : null,
                    ),
                ],
              ),
              const SizedBox(height: 36),
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
                    Text(
                      p.wiiMode.label,
                      style: const TextStyle(
                        color: Color(0xff9bdfc0),
                        fontWeight: FontWeight.w600,
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
              SizedBox(
                // Reserve room for the type strip and motion tester in the
                // default window; larger windows retain the full-size diagram.
                height: pairing.target == ControllerTarget.wii
                    ? (availableHeight -
                              (motion?.showBars == true ? 330 : 285) -
                              (p.stickPointer(d) ? 16 : 0))
                          .clamp(100.0, 250.0)
                    : 280,
                width: double.infinity,
                child: ControllerTester(
                  target: pairing.target,
                  assignment: p,
                  device: d,
                ),
              ),
              if (motion != null) motion,
              if (pairing.target == ControllerTarget.wii)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final mode in WiiMode.values)
                      Expanded(
                        child: Semantics(
                          selected: p.wiiMode == mode,
                          child: InkWell(
                            onTap: m.busy
                                ? null
                                : () => m.wiiMode(p.deviceId, mode),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: p.wiiMode == mode
                                    ? const Color(0xff33534f)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: p.wiiMode == mode
                                      ? const Color(0xff9bdfc0)
                                      : Colors.white12,
                                ),
                              ),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 56,
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

  Widget _action(String label, IconData icon, VoidCallback action) =>
      IconButton(
        tooltip: label,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        iconSize: 18,
        onPressed: model.busy ? null : action,
        icon: Icon(icon),
      );

  Widget _hold(String label, double progress) => SizedBox(
    height: 20,
    child: Row(
      children: [
        SizedBox(
          width: 85,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
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
