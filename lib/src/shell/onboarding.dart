import 'package:flutter/material.dart';

import 'controls.dart';
import 'navigation.dart';
import 'model.dart';
import 'storage.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({super.key, required this.model});
  final ShellModel model;
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  String address = '';
  bool allowHttp = false;
  ShellModel get m => widget.model;
  @override
  Widget build(BuildContext context) {
    final profiles = m.screen == ShellScreen.profiles;
    final wide = MediaQuery.sizeOf(context).width > 950;
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Eyebrow('Your collection. Your way.'),
        const SizedBox(height: 22),
        Text(
          profiles ? "Who’s playing?" : 'A new home\nfor your games.',
          style: TextStyle(
            fontSize: wide ? 59 : 40,
            height: 1.12,
            fontWeight: FontWeight.w300,
            letterSpacing: -1.8,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          profiles
              ? 'Choose a profile on your server,\nor sign in with another account.'
              : 'Connect to your RomM server.\nRediscover everything you love to play.',
          style: const TextStyle(color: muted, fontSize: 17, height: 1.7),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'POWERED BY YOUR ROMM',
              style: TextStyle(fontSize: 10, letterSpacing: 1.8, color: muted),
            ),
          ],
        ),
      ],
    );
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!profiles) ...[
            const Text(
              'Connect your server',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 9),
            const Text(
              'Self-hosted. All yours.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 26),
            if (m.records.servers.isNotEmpty) ...[
              const Eyebrow('Saved servers', color: muted),
              const SizedBox(height: 10),
              for (final server
                  in [...m.records.servers]..sort(
                    (a, b) => a.id == m.records.lastServer
                        ? -1
                        : b.id == m.records.lastServer
                        ? 1
                        : 0,
                  ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ConsoleButton(
                    key: ValueKey(server.id),
                    autofocus:
                        server.id ==
                        (m.records.lastServer ?? m.records.servers.first.id),
                    onPressed: m.busy ? null : () => m.chooseServer(server),
                    child: ActionLabel(
                      Uri.parse(server.address).host,
                      icon: Icons.dns_outlined,
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                'Or add another server',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            ConsoleField(
              label: 'Server address',
              value: address,
              hint: 'https://romm.example.com',
              autofocus: m.records.servers.isEmpty,
              onChanged: (value) => setState(() => address = value),
            ),
            const SizedBox(height: 16),
            if (address.trim().startsWith('http://')) ...[
              ConsoleButton(
                onPressed: () => setState(() => allowHttp = !allowHttp),
                child: Row(
                  children: [
                    Icon(
                      allowHttp
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Allow this HTTP connection',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'HTTP sends your credentials without encryption.',
                style: TextStyle(color: Color(0xffe4bf91), fontSize: 12),
              ),
              const SizedBox(height: 16),
            ],
            ConsoleButton(
              fill: const Color(0xff315b54),
              onPressed: m.busy || address.trim().isEmpty
                  ? null
                  : () => m.addServer(address, allowHttp: allowHttp),
              child: ActionLabel(
                m.busy ? 'Connecting…' : 'Continue',
                icon: Icons.arrow_forward,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Compatible with RomM 5.4.0 · Server addresses are saved on this device.',
              style: TextStyle(color: muted, fontSize: 11, height: 1.5),
            ),
          ] else ...[
            const Eyebrow('Connected server', color: muted),
            const SizedBox(height: 10),
            Text(
              Uri.parse(m.server!.address).host,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Text(
              'RomM ${m.server!.version}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            for (final profile in m.knownProfiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ConsoleButton(
                  key: ValueKey(profile.id),
                  autofocus: profile == m.knownProfiles.first,
                  onPressed: m.busy
                      ? null
                      : () async {
                          final restored = await m.activateProfile(profile);
                          if (context.mounted && restored == false)
                            await showLogin(context, m, profile: profile);
                        },
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xff3d5957),
                        child: Text(
                          profile.name.characters.first.toUpperCase(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              style: const TextStyle(fontSize: 17),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Continue as this player',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ConsoleButton(
              autofocus: m.knownProfiles.isEmpty,
              onPressed: m.busy ? null : () => showLogin(context, m),
              child: const ActionLabel(
                'Add profile',
                icon: Icons.person_add_alt_1_outlined,
              ),
            ),
            const SizedBox(height: 14),
            ConsoleButton(
              fill: Colors.transparent,
              onPressed: m.busy ? null : m.changeServer,
              child: const ActionLabel('Change server', icon: Icons.swap_horiz),
            ),
          ],
          if (m.error != null) ProblemNotice(m.error!),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => ConsoleScrollView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 68 : 28, vertical: 30),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 60).clamp(0, double.infinity),
          ),
          child: wide
              ? Row(
                  children: [
                    Expanded(child: intro),
                    const SizedBox(width: 70),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: form,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [intro, const SizedBox(height: 40), form],
                ),
        ),
      ),
    );
  }
}

Future<void> showLogin(
  BuildContext context,
  ShellModel model, {
  SavedProfile? profile,
}) async {
  model.error = null;
  await showConsoleDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LoginDialog(model: model, profile: profile),
  );
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.model, this.profile});
  final ShellModel model;
  final SavedProfile? profile;
  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  late String username = widget.profile?.name ?? '';
  String secret = '';
  bool token = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) => PopScope(
      canPop: !widget.model.busy,
      child: Dialog(
        backgroundColor: const Color(0xff111d2a),
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 510),
          child: ConsoleScrollView(
            padding: const EdgeInsets.all(32),
            child: FocusTraversalGroup(
              policy: ConsoleTraversalPolicy(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Eyebrow('Welcome to your collection'),
                  const SizedBox(height: 14),
                  Text(
                    widget.profile == null
                        ? 'Sign in to RomM'
                        : 'Welcome back, ${widget.profile!.name}',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Uri.parse(widget.model.server!.address).host,
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 26),
                  if (!token) ...[
                    ConsoleField(
                      label: 'Username',
                      value: username,
                      hint: 'Your RomM username',
                      autofocus: true,
                      onChanged: (v) => setState(() => username = v),
                    ),
                    const SizedBox(height: 18),
                  ],
                  ConsoleField(
                    label: token ? 'Client token or pairing code' : 'Password',
                    value: secret,
                    secret: true,
                    autofocus: token,
                    hint: token
                        ? 'rmm_… or eight-character pairing code'
                        : 'Your RomM password',
                    onChanged: (v) => setState(() => secret = v),
                  ),
                  const SizedBox(height: 18),
                  ConsoleButton(
                    fill: const Color(0xff315b54),
                    onPressed:
                        widget.model.busy ||
                            secret.isEmpty ||
                            (!token && username.trim().isEmpty)
                        ? null
                        : () async {
                            final success = await widget.model.login(
                              username,
                              secret,
                              token: token,
                              expected: widget.profile,
                            );
                            if (mounted && success) {
                              secret = '';
                              Navigator.pop(context);
                            }
                          },
                    child: ActionLabel(
                      widget.model.busy ? 'Signing in…' : 'Sign in',
                      icon: Icons.arrow_forward,
                    ),
                  ),
                  if (widget.model.error != null)
                    ProblemNotice(widget.model.error!),
                  const SizedBox(height: 15),
                  ConsoleButton(
                    fill: Colors.transparent,
                    onPressed: widget.model.busy
                        ? null
                        : () => setState(() {
                            token = !token;
                            secret = '';
                          }),
                    child: Text(
                      token
                          ? 'Use username & password'
                          : 'Use a client token / pairing code',
                      style: const TextStyle(fontSize: 13, color: accent),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    token
                        ? 'Create a RomM client token with profile, games, platforms, assets.read and assets.write access for cloud saves. You can also enter its pairing code.'
                        : 'Your password is used only to sign in and is never saved. Broomm remembers a refresh token in your system secure store.',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ConsoleButton(
                    fill: Colors.transparent,
                    onPressed: widget.model.busy
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
