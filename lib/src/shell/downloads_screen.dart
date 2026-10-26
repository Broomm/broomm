import 'package:flutter/material.dart';

import 'controls.dart';
import 'navigation.dart';
import 'model.dart';
import 'download_status.dart' show byteLabel;

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.model});
  final ShellModel model;
  @override
  Widget build(BuildContext context) {
    final jobs = [
      for (final state in [
        DownloadState.active,
        DownloadState.queued,
        DownloadState.failed,
      ])
        ...model.downloads.where((job) => job.state == state),
    ];
    return ConsoleScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Downloads', style: TextStyle(fontSize: 42)),
          const SizedBox(height: 12),
          Text(
            'Up to ${model.preferences.maxDownloads} simultaneous downloads. You can keep browsing while they install.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 28),
          if (model.downloadQueueNotice != null) ...[
            Text(
              model.downloadQueueNotice!,
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            ConsoleButton(
              autofocus: true,
              onPressed: () => model.loadDownloads(create: true),
              child: const Text('Refresh downloads'),
            ),
            const SizedBox(height: 24),
          ],
          if (model.downloads.isEmpty)
            const Text('Your downloads are complete. Find your games on Home.'),
          for (final (i, job) in jobs.indexed)
            ConsoleFocusRegion(
              child: Container(
                margin: const EdgeInsets.only(bottom: 18),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.game.name, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 8),
                    Text(
                      job.addons ? 'Updates and DLC' : job.game.platform,
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 16),
                    if (job.state == DownloadState.active) ...[
                      LinearProgressIndicator(
                        value: (job.progress?.total ?? 0) > 0
                            ? (job.progress!.received / job.progress!.total)
                                  .clamp(0, 1)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${job.progress?.phase ?? 'Preparing download'} · ${byteLabel(job.progress?.received ?? 0)} / ${byteLabel(job.progress?.total ?? job.game.bytes)}',
                      ),
                    ] else
                      Text(
                        job.problem ?? 'Queued · waiting for a download slot',
                        style: TextStyle(
                          color: job.problem == null
                              ? muted
                              : const Color(0xffefd3aa),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (model.downloadsReadOnly)
                          const Text(
                            'Managed by another Broomm instance',
                            style: TextStyle(color: muted),
                          )
                        else if (job.state == DownloadState.active)
                          ConsoleButton(
                            autofocus: i == 0,
                            onPressed: () => model.cancelDownload(job),
                            child: const Text('Cancel download'),
                          )
                        else ...[
                          if (job.state == DownloadState.failed)
                            ConsoleButton(
                              autofocus: i == 0,
                              onPressed: () => model.retryDownload(job),
                              child: const Text('Retry'),
                            ),
                          ConsoleButton(
                            autofocus:
                                i == 0 && job.state == DownloadState.queued,
                            onPressed: () => model.removeDownload(job),
                            child: Text(
                              job.state == DownloadState.queued
                                  ? 'Remove from queue'
                                  : 'Remove downloaded data',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
