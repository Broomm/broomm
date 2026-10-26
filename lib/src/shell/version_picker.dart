import 'package:flutter/material.dart';

import '../romm/models.dart';
import 'controls.dart';
import 'model.dart';
import 'navigation.dart';

/// Refresh before choosing: a Store representative is not a download identity.
Future<void> downloadGameVersion(
  BuildContext context,
  ShellModel model,
  RommGame game,
) async {
  if (game.versions.length == 1) {
    await model.downloadGame(game);
    return;
  }
  final revision = model.contextRevision;
  await showConsoleDialog<void>(
    context: context,
    builder: (_) =>
        _VersionPicker(model: model, game: game, revision: revision),
  );
}

class _VersionPicker extends StatefulWidget {
  const _VersionPicker({
    required this.model,
    required this.game,
    required this.revision,
  });
  final ShellModel model;
  final RommGame game;
  final int revision;
  @override
  State<_VersionPicker> createState() => _VersionPickerState();
}

class _VersionPickerState extends State<_VersionPicker> {
  RommGame? game;
  String? error;
  bool busy = true;
  bool get current =>
      mounted && widget.model.contextRevision == widget.revision;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.model.detail(widget.game);
      if (current) {
        setState(() {
          game = value;
          busy = false;
        });
        if (value.versions.length == 1 &&
            widget.model.installation(value.id) == null)
          await choose(value.versions.single);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choose(RommVariant version) async {
    if (!current || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await widget.model.detail(
        RommGame(
          id: version.id,
          name: version.name,
          platformId: game!.platformId,
          platform: game!.platform,
        ),
      );
      if (!current) return;
      // The manifest is refreshed again by the actual installation boundary.
      final work = widget.model.downloadGame(selected);
      Navigator.pop(context);
      await work;
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700, maxHeight: 640),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Choose a version', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(widget.game.name, style: const TextStyle(color: muted)),
            const SizedBox(height: 18),
            if (busy) const LinearProgressIndicator(),
            if (error != null) ProblemNotice(error!, retry: load),
            if (game != null)
              Flexible(
                child: ConsoleScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final version in game!.versions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ConsoleButton(
                            key: ValueKey('download-version-${version.id}'),
                            autofocus:
                                version.id ==
                                game!.versions
                                    .where(
                                      (v) =>
                                          widget.model.installation(v.id) ==
                                          null,
                                    )
                                    .firstOrNull
                                    ?.id,
                            onPressed:
                                busy ||
                                    widget.model.installation(version.id) !=
                                        null
                                ? null
                                : () => choose(version),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  version.fileName.isEmpty
                                      ? version.name
                                      : version.fileName,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${game!.platform} · ${widget.model.installation(version.id) == null ? 'Download this version' : 'Already downloaded'} · RomM #${version.id}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            ConsoleButton(
              autofocus: game == null && !busy,
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}
