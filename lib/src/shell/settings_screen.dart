import 'package:flutter/material.dart';

import 'controls.dart';
import 'navigation.dart';
import 'model.dart';
import 'artwork_picker.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.model, required this.openLab});
  final ShellModel model;
  final VoidCallback openLab;
  @override
  Widget build(BuildContext context) => ConsoleScrollView(
    padding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width > 850 ? 68 : 24,
      vertical: 20,
    ),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Eyebrow('Make it yours'),
            const SizedBox(height: 12),
            const Text(
              'Broomm settings',
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w300,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 28),
            if (model.error != null) ProblemNotice(model.error!),
            const Eyebrow('Application updates', color: muted),
            const SizedBox(height: 12),
            Text(
              'Installed: ${model.updates.current}',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 10),
            ConsoleButton(
              onPressed: model.busy
                  ? null
                  : () {
                      const channels = ['auto', 'stable', 'rc'];
                      model.savePreferences(
                        model.preferences.copy(
                          updateChannel:
                              channels[(channels.indexOf(
                                        model.preferences.updateChannel,
                                      ) +
                                      1) %
                                  channels.length],
                        ),
                      );
                    },
              child: ActionLabel(
                'Update channel: ${switch (model.preferences.updateChannel) {
                  'rc' => 'Release candidates',
                  'stable' => 'Stable',
                  _ => 'Match installed release',
                }}',
                icon: Icons.swap_horiz,
              ),
            ),
            const SizedBox(height: 10),
            ConsoleButton(
              onPressed: model.updates.checking || !model.updates.supported
                  ? null
                  : model.updates.check,
              child: ActionLabel(
                model.updates.checking
                    ? 'Checking GitHub…'
                    : 'Check for updates',
                icon: Icons.refresh,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              model.updates.status,
              style: const TextStyle(color: muted, height: 1.5),
            ),
            if (model.updates.available != null) ...[
              const SizedBox(height: 10),
              ConsoleButton(
                onPressed: () => model.navigate(ShellScreen.update),
                child: const ActionLabel(
                  'Update Broomm',
                  icon: Icons.system_update_alt,
                ),
              ),
            ],
            const SizedBox(height: 30),
            const Eyebrow('Appearance', color: muted),
            const SizedBox(height: 12),
            _toggle(
              context,
              'Reduce motion',
              'Use instant transitions and focus scrolling.',
              model.preferences.reduceMotion,
              () => model.savePreferences(
                model.preferences.copy(
                  reduceMotion: !model.preferences.reduceMotion,
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            _toggle(
              context,
              'Show game artwork',
              'Display covers and backgrounds from your RomM server.',
              model.preferences.showArtwork,
              () => model.savePreferences(
                model.preferences.copy(
                  showArtwork: !model.preferences.showArtwork,
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Eyebrow('Game Store', color: muted),
            const SizedBox(height: 12),
            ConsoleButton(
              onPressed: model.busy
                  ? null
                  : () => model.savePreferences(
                      model.preferences.copy(
                        pageSize: model.preferences.pageSize == 24 ? 48 : 24,
                      ),
                    ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Games per page',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Change how many games load at a time.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${model.preferences.pageSize}',
                    style: const TextStyle(color: accent, fontSize: 18),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.swap_horiz, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Eyebrow('Downloads', color: muted),
            const SizedBox(height: 12),
            ConsoleButton(
              onPressed: model.busy
                  ? null
                  : () => model.savePreferences(
                      model.preferences.copy(
                        maxDownloads: model.preferences.maxDownloads % 6 + 1,
                      ),
                    ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Maximum simultaneous downloads',
                          style: TextStyle(fontSize: 16),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Download up to six games at once. Emulator installation stays sequential.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${model.preferences.maxDownloads}',
                    style: const TextStyle(color: accent, fontSize: 18),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.swap_horiz, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _toggle(
              context,
              'Verify game checksums',
              'Optional full-file CRC32 scan after download. Complete transfer sizes are always checked.',
              model.preferences.verifyDownloads,
              () => model.savePreferences(
                model.preferences.copy(
                  verifyDownloads: !model.preferences.verifyDownloads,
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Eyebrow('Game artwork', color: muted),
            const SizedBox(height: 12),
            ConsoleButton(
              onPressed: model.busy
                  ? null
                  : () => steamGridSettings(context, model),
              child: const ActionLabel(
                'SteamGridDB API key',
                icon: Icons.collections_outlined,
              ),
            ),
            const SizedBox(height: 30),
            const Eyebrow('Your account', color: muted),
            const SizedBox(height: 12),
            ConsoleFocusRegion(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.profile?.name ?? '',
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      model.server?.address ?? '',
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'RomM ${model.server?.version ?? ''}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        ConsoleButton(
                          onPressed: model.busy ? null : model.switchAccount,
                          child: const ActionLabel(
                            'Switch profile',
                            icon: Icons.person_outline,
                          ),
                        ),
                        ConsoleButton(
                          onPressed: model.busy ? null : model.signOut,
                          child: const ActionLabel(
                            'Sign out on this device',
                            icon: Icons.logout,
                          ),
                        ),
                        ConsoleButton(
                          onPressed: model.busy ? null : model.changeServer,
                          child: const ActionLabel(
                            'Change server',
                            icon: Icons.dns_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Sign-ins are remembered in your system secure store. Switching profiles keeps them; signing out removes this profile’s saved sign-in. Passwords are never saved.',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Eyebrow('Controller lab', color: muted),
            const SizedBox(height: 12),
            ConsoleButton(
              onPressed: openLab,
              child: const ActionLabel(
                'Open local controller test games',
                icon: Icons.sports_esports_outlined,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Uses the existing six local ROM fixtures and private prototype emulator data. RomM games are not installed or launched by this tool.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 28),
            const Text(
              'BROOMM  /  YOUR GAMES, TOGETHER.',
              style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.6),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
  );
  Widget _toggle(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    VoidCallback action, {
    bool autofocus = false,
  }) => ConsoleButton(
    autofocus: autofocus,
    onPressed: model.busy ? null : action,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        ExcludeFocus(
          child: Switch(
            value: value,
            onChanged: model.busy ? null : (_) => action(),
            activeThumbColor: accent,
          ),
        ),
      ],
    ),
  );
}
