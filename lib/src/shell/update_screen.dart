import 'package:flutter/material.dart';

import 'controls.dart';
import 'model.dart';
import 'navigation.dart';

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key, required this.model, required this.install});
  final ShellModel model;
  final Future<void> Function() install;
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.install();
    });
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.model.updates;
    return ConsoleScrollView(
      padding: const EdgeInsets.all(48),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('Ready for what’s next'),
              const SizedBox(height: 20),
              Text(
                'Update Broomm${update.available == null ? '' : ' to ${update.available!.version}'}',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                update.status,
                style: const TextStyle(fontSize: 19, height: 1.5),
              ),
              const SizedBox(height: 22),
              if (update.busy) ...[
                LinearProgressIndicator(value: update.progress),
                const SizedBox(height: 18),
                if (update.progress != null)
                  Text(
                    '${(update.progress! * 100).round()}%',
                    style: const TextStyle(color: muted),
                  ),
              ],
              const SizedBox(height: 22),
              const Text(
                'Your games, emulator settings and saved progress stay on this device. Resume interrupted game transfers from Downloads after restarting.',
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 30),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  if (update.busy && !update.handedOff)
                    ConsoleButton(
                      autofocus: true,
                      onPressed: update.cancel,
                      child: const ActionLabel(
                        'Cancel update',
                        icon: Icons.close,
                      ),
                    ),
                  if (!update.busy &&
                      !update.handedOff &&
                      update.available != null)
                    ConsoleButton(
                      autofocus: true,
                      onPressed: widget.install,
                      child: const ActionLabel(
                        'Continue installation',
                        icon: Icons.system_update_alt,
                      ),
                    ),
                  if (!update.busy)
                    ConsoleButton(
                      onPressed: () => widget.model.navigate(ShellScreen.home),
                      child: const ActionLabel(
                        'Back to Home',
                        icon: Icons.arrow_back,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
