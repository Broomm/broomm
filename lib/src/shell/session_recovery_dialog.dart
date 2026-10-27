import 'dart:async';

import 'package:flutter/material.dart';

import '../host.dart';
import 'controls.dart';
import 'navigation.dart';

Future<Map<String, dynamic>?> _inspect(DesktopHost host, String root) async {
  try {
    return await host.gameWriter(root).timeout(const Duration(seconds: 3));
  } catch (error) {
    return {
      'status': 'unknown',
      'message': 'The previous session could not be checked. $error',
    };
  }
}

Future<bool> recoverGameSession(
  BuildContext context,
  String root, {
  DesktopHost? host,
}) async {
  final adapter = host ?? DesktopHost();
  final writer = await _inspect(adapter, root);
  if (writer == null) return true;
  if (!context.mounted) return false;
  return await showConsoleDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _SessionRecovery(root: root, host: adapter, initial: writer),
      ) ??
      false;
}

class _SessionRecovery extends StatefulWidget {
  const _SessionRecovery({
    required this.root,
    required this.host,
    required this.initial,
  });
  final String root;
  final DesktopHost host;
  final Map<String, dynamic> initial;
  @override
  State<_SessionRecovery> createState() => _SessionRecoveryState();
}

class _SessionRecoveryState extends State<_SessionRecovery> {
  late Map<String, dynamic> writer = widget.initial;
  Timer? timer;
  bool checking = false, working = false;
  String? problem;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(check()),
    );
  }

  Future<void> check() async {
    if (checking || !mounted) return;
    checking = true;
    try {
      final next = await _inspect(widget.host, widget.root);
      if (!mounted) return;
      if (next == null) {
        final route = ModalRoute.of(context);
        if (route?.isCurrent == true) {
          Navigator.pop(context, true);
        } else if (route != null) {
          Navigator.of(context).removeRoute(route, true);
        }
      } else {
        setState(() => writer = next);
      }
    } finally {
      checking = false;
    }
  }

  Future<void> control(String action) async {
    final token = writer['token'] as String?;
    if (token == null || working) return;
    if (action == 'force') {
      final confirmed = await showConsoleDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Force quit the emulator?',
                  style: TextStyle(fontSize: 26),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Unsaved progress can be lost. Existing saves and Broomm recovery copies will be kept. Only the verified emulator holding this game lock will be stopped.',
                  style: TextStyle(color: muted, height: 1.6),
                ),
                const SizedBox(height: 22),
                ConsoleButton(
                  autofocus: true,
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(height: 12),
                ConsoleButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Force quit emulator'),
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      working = true;
      problem = null;
    });
    try {
      await widget.host
          .controlGameWriter(token, action)
          .timeout(const Duration(seconds: 3));
      if (action != 'show') await check();
    } catch (error) {
      if (mounted) setState(() => problem = '$error');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: ConsoleScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Recover game session', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 18),
            Text(
              writer['message'] as String? ??
                  'An emulator still owns this session.',
              style: const TextStyle(color: muted, height: 1.6),
            ),
            if (problem != null) ...[
              const SizedBox(height: 12),
              ProblemNotice(problem!),
            ],
            if (writer['status'] == 'emulator') ...[
              const SizedBox(height: 22),
              ConsoleButton(
                autofocus: true,
                onPressed: working ? null : () => control('show'),
                child: Text('Show ${writer['name'] ?? 'emulator'}'),
              ),
              const SizedBox(height: 12),
              ConsoleButton(
                onPressed: working ? null : () => control('stop'),
                child: const Text('Close emulator normally'),
              ),
              const SizedBox(height: 12),
              ConsoleButton(
                onPressed: working ? null : () => control('force'),
                child: const Text('Force quit emulator…'),
              ),
            ],
            const SizedBox(height: 12),
            ConsoleButton(onPressed: check, child: const Text('Check again')),
            const SizedBox(height: 12),
            ConsoleButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    ),
  );
}
