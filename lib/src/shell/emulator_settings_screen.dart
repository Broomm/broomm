import 'dart:async';

import 'package:flutter/material.dart';

import '../game_launch.dart';
import '../managed_emulators.dart';
import '../retroarch.dart';
import '../romm/models.dart';
import 'controls.dart';
import 'navigation.dart';
import 'model.dart';
import 'android_emulator_settings_screen.dart';

class EmulatorSettingsScreen extends StatefulWidget {
  const EmulatorSettingsScreen({super.key, required this.model});
  final ShellModel model;
  @override
  State<EmulatorSettingsScreen> createState() => _EmulatorSettingsScreenState();
}

class _EmulatorSettingsScreenState extends State<EmulatorSettingsScreen> {
  ShellModel get model => widget.model;
  ManagedEmulators get m => model.emulators;
  final reviews = <String, SetupPlan>{};
  final problems = <String, String>{};
  final imported = <String, SetupItem>{};
  final setupFocus = <String, FocusNode>{};
  final scope = FocusScopeNode(
    debugLabel: 'Emulator settings',
    traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );
  final policy = OrderedTraversalPolicy(
    requestFocusCallback: requestConsoleFocus,
  );
  String? active, reviewing, completed, importProblem;
  String path = '';
  String keyFor(RommPlatform p, TestedBuild b) => '${p.id}:${b.id}';
  @override
  void dispose() {
    for (final node in setupFocus.values) {
      node.dispose();
    }
    scope.dispose();
    super.dispose();
  }

  void focusCard(String key) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && setupFocus[key]?.canRequestFocus == true)
          requestConsoleFocus(setupFocus[key]!);
      });

  Future<void> review(RommPlatform platform, TestedBuild build) async {
    if (reviewing != null) return;
    final key = keyFor(platform, build);
    model.setupPlatformId = null;
    setState(() {
      active = key;
      reviewing = key;
      completed = null;
      reviews.remove(key);
      problems.remove(key);
    });
    try {
      final plan = imported.containsKey(build.id)
          ? SetupPlan([imported[build.id]!])
          : await m.readPlan(only: {build.id});
      if (mounted) setState(() => reviews[key] = plan);
    } catch (e) {
      if (mounted) setState(() => problems[key] = '$e');
    } finally {
      if (mounted) setState(() => reviewing = null);
    }
  }

  Future<void> importSetup() async {
    final selected = await showConsoleDialog<String>(
      context: context,
      builder: (_) => _SetupPathDialog(initial: path),
    );
    if (selected == null || !mounted) return;
    path = selected;
    model.setupPlatformId = null;
    setState(() => importProblem = null);
    try {
      final plan = await m.readPlan(file: selected);
      if (!mounted) return;
      setState(() {
        imported.clear();
        for (final item in plan.items) {
          imported[item.build.id] = item;
        }
        active = null;
        for (final platform in model.platforms) {
          for (final choice in platformEmulators(platform)) {
            final b = m.buildFor(choice.emulator);
            if (b != null && imported.containsKey(b.id)) {
              final key = keyFor(platform, b);
              reviews[key] = SetupPlan([imported[b.id]!]);
              active ??= key;
            }
          }
        }
        if (active == null) importProblem = 'This setup file has no emulators supported for the platforms on this server.';
      });
    } catch (e) {
      if (mounted) setState(() => importProblem = '$e');
    }
  }

  Future<void> remove(RommPlatform platform, TestedBuild build) async {
    final affected = model.platforms
        .where((p) => platformEmulators(p).any((e) => e.emulator == build.name))
        .map((p) => p.name)
        .join(', ');
    final confirmed = await showConsoleDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: ConsoleScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Remove ${build.name}?',
                  style: const TextStyle(fontSize: 26),
                ),
                const SizedBox(height: 18),
                Text(
                  'This removes the shared managed application, core and installation resources for $affected, across all Broomm profiles. Profile settings, saves, save states and downloaded games are kept.',
                  style: const TextStyle(color: muted, height: 1.7),
                ),
                const SizedBox(height: 22),
                ConsoleButton(
                  autofocus: true,
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(height: 12),
                ConsoleButton(
                  key: ValueKey('confirm-remove-${build.id}'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Remove emulator'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final key = keyFor(platform, build);
    setState(() {
      active = key;
      completed = null;
      reviews.remove(key);
      problems.remove(key);
      model.setupPlatformId = null;
    });
    await model.finishCloud();
    await m.remove(build);
    if (mounted && m.error == null)
      setState(() {
        active = null;
        completed = key;
      });
    focusCard(key);
  }

  bool direction(TraversalDirection direction) {
    if (direction != TraversalDirection.down) return false;
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return false;
    // Let directional traversal follow the rendered rows, including Wrap's
    // compact layout. Only stop the final row from escaping into the header.
    return !scope.traversalDescendants.any(
      (other) => other != node && other.rect.top >= node.rect.bottom - .5,
    );
  }

  @override
  Widget build(BuildContext context) => model.isAndroid
      ? AndroidEmulatorSettingsScreen(model: model)
      : ListenableBuilder(
          listenable: Listenable.merge([model, m]),
          builder: (context, _) => ConsoleDirections(
            onDirection: direction,
            child: FocusScope(
              node: scope,
              child: FocusTraversalGroup(
                policy: policy,
                child: LayoutBuilder(
                  builder: (context, size) => ConsoleScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: size.maxWidth > 850 ? 56 : 24,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Eyebrow('A great setup, made simple'),
                        const SizedBox(height: 14),
                        const Text(
                          'Emulator Settings',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w300,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Your platforms. Your way to play.',
                          style: TextStyle(fontSize: 21),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Set up an emulator for each platform in your RomM library. The default is used when you press Play. Settings and progress stay private to your Broomm profile.',
                          style: TextStyle(color: muted, height: 1.7),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ConsoleButton(
                              autofocus: true,
                              order: 0,
                              onPressed: m.busy || model.platformsLoading
                                  ? null
                                  : () async {
                                      await m.load();
                                      await model.refreshPlatforms();
                                    },
                              child: const ActionLabel(
                                'Refresh status',
                                icon: Icons.refresh,
                              ),
                            ),
                            ConsoleButton(
                              order: 1,
                              onPressed: m.busy || !m.supported
                                  ? null
                                  : importSetup,
                              child: const ActionLabel(
                                'Import setup JSON',
                                icon: Icons.file_open_outlined,
                              ),
                            ),
                          ],
                        ),
                        if (!m.supported)
                          const ProblemNotice(
                            'The first tested setup pack is for macOS Apple Silicon. Other hosts need their own validated emulator packages. Android uses external emulator apps.',
                          ),
                        if (model.discoveryError != null)
                          ProblemNotice(
                            model.discoveryError!,
                            retry: model.refreshPlatforms,
                          ),
                        if (importProblem != null)
                          ProblemNotice(importProblem!),
                        if (m.error != null &&
                            active == null &&
                            model.setupPlatformId == null)
                          ProblemNotice(m.error!),
                        if (!model.platformsLoaded && model.platformsLoading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Loading platforms from RomM…'),
                          ),
                        if (model.platformsLoaded && model.platforms.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'This RomM server has no platforms yet.',
                              style: TextStyle(color: muted),
                            ),
                          ),
                        const SizedBox(height: 30),
                        for (final p
                            in [...model.platforms]..sort(
                              (a, b) => a.name.toLowerCase().compareTo(
                                b.name.toLowerCase(),
                              ),
                            )) ...[
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${p.count} games',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          if (platformEmulators(p).isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 14),
                              child: Text(
                                'No supported emulators for this platform yet.',
                                style: TextStyle(color: muted),
                              ),
                            ),
                          for (final choice in platformEmulators(p))
                            if (m.buildFor(choice.emulator)
                                case final TestedBuild build)
                              _card(p, build),
                          const SizedBox(height: 26),
                        ],
                        const Text(
                          'Emulator installations are shared. Defaults belong to this server; each profile has separate settings, saves and save states. Updates run only when you start setup.',
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

  Widget _card(RommPlatform platform, TestedBuild build) {
    final key = keyFor(platform, build);
    final ready = m.readyFor(build.name, platform.slug);
    final sorted = [...model.platforms]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final order =
        10.0 +
        sorted.indexWhere((p) => p.id == platform.id) * 1000 +
        platformEmulators(platform)
                .indexWhere((p) => p.emulator == build.name) *
            10;
    final isDefault = model.defaultEmulator(platform) == build.id;
    final inherited =
        active == null &&
        model.setupPlatformId == platform.id &&
        (m.plan?.items.any((item) => item.build.id == build.id) ?? false);
    final expanded = active == key || inherited;
    final plan = reviews[key] ?? (inherited ? m.plan : null);
    final disabled =
        m.busy ||
        model.gameActive ||
        (reviewing != null && reviewing != key) ||
        !m.supported;
    return ConsoleFocusRegion(
      child: Container(
        key: ValueKey('emulator-card-$key'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDefault
                ? accent
                : expanded
                ? accent.withValues(alpha: .5)
                : Colors.white10,
            width: isDefault ? 2 : 1,
          ),
        ),
        child: AnimatedSize(
          duration: motionDuration(context),
          curve: consoleCurve,
          alignment: Alignment.topCenter,
          onEnd: () {
            if (FocusManager.instance.primaryFocus case final node?)
              revealConsoleFocus(node);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    ready ? Icons.check_circle_outline : Icons.memory_rounded,
                    color: ready ? accent : muted,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          build.id == 'retroarch' &&
                                  retroSystem(platform.slug) != null
                              ? 'RetroArch / ${retroSystem(platform.slug)!.label}'
                              : build.name,
                          style: const TextStyle(fontSize: 21),
                        ),
                        if (build.architecture == 'x64' &&
                            m.host == 'macos-arm64')
                          const Text(
                            'Intel x86_64 · Rosetta required on Apple Silicon',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          build.version,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (isDefault)
                    const Padding(
                      padding: EdgeInsets.only(left: 10),
                      child: Text(
                        'Default',
                        style: TextStyle(color: accent, fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                ready
                    ? m.resourceProblems[build.id] ?? 'Ready to play'
                    : 'Not set up',
                style: TextStyle(color: ready ? accent : muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  ConsoleButton(
                    key: ValueKey('setup-$key'),
                    order: order,
                    focusNode: setupFocus.putIfAbsent(key, FocusNode.new),
                    onPressed: disabled || m.removals.containsKey(build.id)
                        ? null
                        : () => review(platform, build),
                    child: ActionLabel(
                      reviewing == key
                          ? 'Preparing setup…'
                          : ready
                          ? 'Verify setup'
                          : 'Set up',
                      icon: Icons.tune_rounded,
                    ),
                  ),
                  if (ready || m.removals.containsKey(build.id))
                    ConsoleButton(
                      key: ValueKey('remove-$key'),
                      order: order + 1,
                      onPressed: disabled
                          ? null
                          : () => remove(platform, build),
                      child: ActionLabel(
                        m.removals.containsKey(build.id)
                            ? 'Finish removal'
                            : 'Remove',
                        icon: Icons.delete_outline,
                      ),
                    ),
                  if (ready)
                    ConsoleButton(
                      key: ValueKey('open-$key'),
                      order: order + 1.5,
                      onPressed: disabled || model.downloading
                          ? null
                          : () => model.openEmulator(build.name),
                      child: ActionLabel(
                        model.configurationEmulator == build.name
                            ? 'Quit emulator to return'
                            : 'Open emulator',
                        icon: Icons.open_in_new,
                      ),
                    ),
                  if (!isDefault)
                    ConsoleButton(
                      key: ValueKey('default-$key'),
                      order: order + 2,
                      onPressed: ready && !disabled
                          ? () => model.setDefaultEmulator(platform, build.id)
                          : null,
                      child: const Text('Set as default'),
                    ),
                ],
              ),
              if (completed == key)
                Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(m.notice, style: TextStyle(color: accent)),
                ),
              if (expanded) ...[
                const SizedBox(height: 20),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                if (problems[key] != null) ProblemNotice(problems[key]!),
                if (m.error != null) ProblemNotice(m.error!),
                if (m.busy && plan == null) ...[
                  Text(m.phase),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (plan != null) ...[
                  const Text('Ready to set up', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 10),
                  for (final item in plan.items.where(
                    (i) => i.build.id == build.id,
                  )) ...[
                    Text(
                      'Application: ${item.source}',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.7,
                      ),
                    ),
                    if (item.core != null)
                      Text(
                        'Core: ${item.core}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    if (item.cores.isNotEmpty)
                      Text(
                        'Includes ${item.cores.length} additional console cores.',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    for (final entry in item.resources.entries)
                      Text(
                        '${resourceName(entry.key)}: ${entry.value}',
                        style: const TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.7,
                        ),
                      ),
                    if (build.isRpcs3 &&
                        !item.resources.containsKey('ps3_firmware'))
                      const Text(
                        'Missing firmware will be downloaded from this platform’s RomM BIOS catalogue before play, when available.',
                        style: TextStyle(color: Color(0xffefd3aa)),
                      ),
                    if (build.id == 'ryubing' &&
                        (!item.resources.containsKey('prod_keys') ||
                            !item.resources.containsKey('title_keys') ||
                            !item.resources.containsKey('switch_firmware')))
                      const Text(
                        'Before play, Broomm can install one firmware ZIP, prod.keys and title.keys from the Switch platform’s RomM BIOS catalogue.',
                        style: TextStyle(color: Color(0xffefd3aa)),
                      ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'Broomm will verify and install its own copy. Existing profile progress and system emulator settings are preserved.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.7),
                  ),
                  const SizedBox(height: 16),
                  if (m.busy) ...[
                    Text(m.phase),
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    ConsoleButton(
                      onPressed: m.cancel,
                      order: order + 3,
                      child: const Text('Cancel setup'),
                    ),
                  ] else
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        ConsoleButton(
                          key: ValueKey('confirm-$key'),
                          order: order + 3,
                          fill: const Color(0xff315b54),
                          onPressed: () async {
                            await model.finishCloud();
                            await m.install(
                              SetupPlan(
                                plan.items
                                    .where((i) => i.build.id == build.id)
                                    .toList(),
                              ),
                            );
                            unawaited(model.retryCloud());
                            if (mounted && m.error == null)
                              setState(() {
                                completed = key;
                                active = null;
                                model.setupPlatformId = null;
                                reviews.remove(key);
                              });
                            focusCard(key);
                          },
                          child: const ActionLabel(
                            'Start setup',
                            icon: Icons.download_done_outlined,
                          ),
                        ),
                        ConsoleButton(
                          order: order + 4,
                          onPressed: () {
                            setState(() {
                              active = null;
                              model.setupPlatformId = null;
                              reviews.remove(key);
                            });
                            focusCard(key);
                          },
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupPathDialog extends StatefulWidget {
  const _SetupPathDialog({required this.initial});
  final String initial;
  @override
  State<_SetupPathDialog> createState() => _SetupPathDialogState();
}

class _SetupPathDialogState extends State<_SetupPathDialog> {
  late String value = widget.initial;
  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: ConsoleScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Import setup JSON', style: TextStyle(fontSize: 25)),
            const SizedBox(height: 20),
            ConsoleField(
              autofocus: true,
              label: 'Setup JSON path',
              value: value,
              hint: '/path/to/setup.json',
              onChanged: (v) => setState(() => value = v),
            ),
            const SizedBox(height: 18),
            ConsoleButton(
              onPressed: value.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, value.trim()),
              child: const Text('Review setup file'),
            ),
            const SizedBox(height: 12),
            ConsoleButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}

String resourceName(String key) => switch (key) {
  'ps3_firmware' => 'PS3 firmware',
  'switch_firmware' => 'Switch firmware',
  'prod_keys' => 'Switch production keys',
  'title_keys' => 'Switch title keys',
  _ => key,
};
