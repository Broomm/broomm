import 'package:flutter/material.dart';

import '../progress/service.dart';
import '../romm/client.dart';
import '../romm/models.dart';
import 'controls.dart';
import 'model.dart';
import 'navigation.dart';
import 'onboarding.dart';

Future<ProgressChoice> resolveCloudConflict(
  BuildContext context,
  ProgressConflict conflict,
) async =>
    await showConsoleDialog<ProgressChoice>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Choose your progress'),
        content: SizedBox(
          width: 540,
          child: Text(
            '${conflict.reason}\n\nDevice copy: ${conflict.local.manifest['created']}\n${conflict.remote == null ? 'Cloud copy: unavailable' : 'Cloud copy: ${conflict.remote!.manifest['created']}'}\n\nThe unselected copy stays in local recovery storage. Other RomM save files are not changed.',
          ),
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, ProgressChoice.cancel),
            child: const Text('Cancel'),
          ),
          if (conflict.remote != null)
            ConsoleButton(
              onPressed: () => Navigator.pop(c, ProgressChoice.cloud),
              child: const Text('Use cloud progress'),
            ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, ProgressChoice.device),
            child: const Text('Use device progress'),
          ),
        ],
      ),
    ) ??
    ProgressChoice.cancel;

Future<void> manageCloudSaves(
  BuildContext context,
  ShellModel model,
  RommGame game,
  String action,
) async {
  if (model.isAndroid) {
    final closed = await showConsoleDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close the emulator first'),
        content: const Text(
          'Save and exit the Android emulator before importing, backing up or synchronizing progress. Switching applications can leave it running in the background.',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Emulator closed · Continue'),
          ),
        ],
      ),
    );
    if (closed != true || !context.mounted) return;
  }
  if (!context.mounted) return;
  await showConsoleDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SaveDialog(model: model, game: game, action: action),
  );
}

class _SaveDialog extends StatefulWidget {
  const _SaveDialog({
    required this.model,
    required this.game,
    required this.action,
  });
  final ShellModel model;
  final RommGame game;
  final String action;
  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  bool working = false, authorize = false;
  String? message;
  String name = '';
  List<RommSave>? saves;
  int savePage = 0;
  ShellModel get m => widget.model;
  @override
  void initState() {
    super.initState();
    if (widget.action == 'save-use') load();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      working = true;
      message = null;
      authorize = false;
    });
    try {
      await m.cloudAction(action);
    } catch (e) {
      if (mounted)
        setState(() {
          message = progressFailure(e);
          authorize = e is RommFailure && [401, 403].contains(e.status);
        });
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> load() => run(() async {
    final g = await m.cloudGame(widget.game.id);
    final list = await m.cloud.list(g);
    if (mounted)
      setState(() {
        savePage = 0;
        saves = list
            .where((s) => !s.missing && !s.name.startsWith('.broomm-backup-'))
            .toList();
      });
  });
  Future<void> choose(RommSave save) async {
    final yes = await showConsoleDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Use ${save.name}?'),
        content: const Text(
          'Copy this save into a new BROOMM version and use it on this device? Earlier cloud versions and local recovery copies are kept. The source stays unchanged. Import a DS .sav, SNES .srm, GameCube .gci, an exported game-save directory ZIP or a Broomm backup.',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Use this save'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await run(() async {
      final g = await m.cloudGame(widget.game.id);
      await m.cloud.useExisting(g, save);
      if (mounted)
        setState(
          () => message =
              'Saved as a new BROOMM version. Your original save is unchanged.',
        );
    });
  }

  Future<void> backup() => run(() async {
    final g = await m.cloudGame(widget.game.id);
    await m.cloud.backup(g, name);
    if (mounted)
      setState(
        () => message = 'Backup created. Automatic sync uses the BROOMM slot.',
      );
  });
  Future<void> sync() => run(() async {
    final g = await m.cloudGame(widget.game.id);
    await m.cloud.sync(
      g,
      resolve: (conflict) => resolveCloudConflict(context, conflict),
    );
    if (mounted)
      setState(
        () => message =
            'Cloud save check completed. Only BROOMM history was synced.',
      );
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !working,
    child: Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        child: ConsoleScrollView(
          padding: const EdgeInsets.all(30),
          child: FocusTraversalGroup(
            policy: ConsoleTraversalPolicy(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.action == 'save-use'
                      ? 'Use existing save file'
                      : widget.action == 'save-backup'
                      ? 'Backup savefile'
                      : 'Cloud saves',
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(height: 12),
                Text(widget.game.name),
                const SizedBox(height: 12),
                const Text(
                  'Automatic sync uses the latest version in this game’s BROOMM slot for your current RomM account. Each changed save adds “Broomm [yyyy-mm-dd_hh-mm-ss]” with its native extension; directory saves use ZIP. Older versions and other slots are kept.',
                ),
                const SizedBox(height: 22),
                if (working) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text(
                    'Checking or transferring progress… Local recovery copies are retained.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (!working && m.cloudBusy) ...[
                  ConsoleButton(
                    onPressed: () async {
                      await m.finishCloud();
                      if (mounted) setState(() {});
                    },
                    child: const Text('Pause automatic sync'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (message != null) ...[
                  Text(message!),
                  const SizedBox(height: 18),
                ],
                if (!working && authorize) ...[
                  ConsoleButton(
                    onPressed: () async {
                      await showLogin(context, m, profile: m.profile);
                      if (mounted)
                        setState(() {
                          authorize = false;
                          saves = null;
                        });
                    },
                    child: const Text('Sign in to authorize cloud saves'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!working && widget.action == 'save-use') ...[
                  if (saves == null || saves!.isEmpty)
                    Text(
                      saves == null ? 'Read the save list to choose a source.' : 'There are no available saves for this game and account.',
                    ),
                  for (final save
                      in (saves ?? <RommSave>[]).skip(savePage * 20).take(20))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ConsoleButton(
                        onPressed: () => choose(save),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(save.name),
                            Text(
                              '${save.emulator ?? 'Emulator not specified'}${save.slot == null ? '' : ' · ${save.slot}'} · ${save.bytes} bytes · ${save.updated}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (saves != null && saves!.length > 20) ...[
                    Text(
                      'Page ${savePage + 1} of ${(saves!.length + 19) ~/ 20}',
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        ConsoleButton(
                          onPressed: savePage > 0
                              ? () => setState(() => savePage--)
                              : null,
                          child: const Text('Previous saves'),
                        ),
                        ConsoleButton(
                          onPressed: (savePage + 1) * 20 < saves!.length
                              ? () => setState(() => savePage++)
                              : null,
                          child: const Text('Next saves'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  ConsoleButton(
                    onPressed: load,
                    child: const Text('Refresh save list'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.action == 'save-backup') ...[
                  const Text(
                    'The correct file extension is added automatically. An interrupted backup resumes its original snapshot when retried. Existing named saves are never overwritten.',
                  ),
                  const SizedBox(height: 12),
                  ConsoleField(
                    label: 'Backup name',
                    value: name,
                    maxLength: 100,
                    onChanged: (v) => setState(() => name = v),
                    hint: 'Before the final boss',
                  ),
                  const SizedBox(height: 12),
                  ConsoleButton(
                    onPressed: working || name.trim().isEmpty ? null : backup,
                    child: const Text('Create backup in RomM'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.action == 'save-sync') ...[
                  const Text(
                    'Sync ordinary saves and supported states. Incompatible states are kept separately by emulator build and host. An unexpected emulator exit requires a progress choice.',
                  ),
                  const SizedBox(height: 12),
                  ConsoleButton(
                    onPressed: working ? null : sync,
                    child: const Text('Sync / resolve conflict'),
                  ),
                  const SizedBox(height: 12),
                ],
                ConsoleButton(
                  autofocus: true,
                  onPressed: working
                      ? m.cloud.cancel
                      : () => Navigator.pop(context),
                  child: Text(working ? 'Cancel transfer' : 'Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
