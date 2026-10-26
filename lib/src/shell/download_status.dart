import 'package:flutter/material.dart';

import '../romm/models.dart';
import 'controls.dart';
import 'model.dart';
import '../game_launch.dart';
import 'version_picker.dart';

String byteLabel(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
    : bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(1)} KB';

class DownloadStatus extends StatelessWidget {
  const DownloadStatus({super.key, required this.model, this.game});
  final ShellModel model;
  final RommGame? game;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final currentRoute = ModalRoute.of(context)?.isCurrent == true;
      final progress = model.download,
          installed = game == null ? null : model.installation(game!.id);
      if (game != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              installed == null
                  ? 'Add to your library'
                  : installed.problem != null
                  ? 'Files need attention'
                  : 'Downloaded',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              installed?.problem ??
                  (installed != null
                      ? 'Available on Home. Progress syncs with this profile’s BROOMM history in RomM.'
                      : 'Download the game files to this device, then launch supported platforms from Home.'),
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (installed != null &&
                installed.problem == null &&
                gamePlatform(installed.game, model.platforms) != null)
              ConsoleButton(
                autofocus: currentRoute,
                onPressed: () => requestPlay(context, installed.game.id),
                fill: const Color(0xff315b54),
                child: const ActionLabel(
                  'Play',
                  icon: Icons.play_arrow_rounded,
                ),
              ),
            if (model.downloadError != null)
              ProblemNotice(model.downloadError!),
            if (model.downloadMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  model.downloadMessage!,
                  style: const TextStyle(color: accent, fontSize: 12),
                ),
              ),
            if (installed == null || game!.siblings.isNotEmpty)
              ConsoleButton(
                autofocus: currentRoute,
                onPressed: model.queuedGame(game!.id) != null
                    ? () {
                        Navigator.of(context).pop();
                        model.navigate(ShellScreen.downloads);
                      }
                    : () => downloadGameVersion(context, model, game!),
                child: ActionLabel(
                  model.queuedGame(game!.id) != null
                      ? 'View in Downloads'
                      : installed != null
                      ? 'Download another version'
                      : 'Download game',
                  icon: Icons.download_outlined,
                ),
              ),
          ],
        );
      }
      if (progress != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              progress.game.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.total > 0
                  ? (progress.received / progress.total).clamp(0, 1)
                  : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${progress.phase} · ${byteLabel(progress.received)} / ${byteLabel(progress.total)}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                ConsoleButton(
                  autofocus: game != null && currentRoute,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  onPressed: model.cancelDownload,
                  child: const Text('Cancel download'),
                ),
              ],
            ),
          ],
        );
      }
      final notice = model.downloadError ?? model.downloadMessage;
      if (notice == null) return const SizedBox.shrink();
      return Row(
        children: [
          Expanded(
            child: Text(
              notice,
              style: TextStyle(
                color: model.downloadError != null
                    ? const Color(0xffefd3aa)
                    : accent,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ConsoleButton(
            padding: const EdgeInsets.all(10),
            label: 'Dismiss download notice',
            onPressed: model.dismissDownloadNotice,
            child: const Icon(Icons.close, size: 18),
          ),
        ],
      );
    },
  );
}
