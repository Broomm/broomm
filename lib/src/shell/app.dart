import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitType, AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_model.dart';
import '../catalogue.dart';
import '../host.dart';
import '../../controller_lab.dart';
import 'controls.dart';
import 'navigation.dart';
import 'notifications.dart';
import 'home_screen.dart';
import 'downloads_screen.dart';
import 'model.dart';
import 'onboarding.dart';
import 'settings_screen.dart';
import 'store_screen.dart';
import 'controller_input.dart';
import '../game_launch.dart';
import '../session.dart';
import 'game_session_screen.dart';
import 'emulator_settings_screen.dart';
import 'artwork_picker.dart';
import 'artwork.dart' show HomeBackground;
import '../progress/service.dart';
import '../ps3_firmware.dart';
import '../playstation_firmware.dart';
import '../retroarch_firmware.dart';
import '../switch_firmware.dart';
import '../progress/ryubing.dart';
import 'cloud_saves_dialog.dart';
import '../android/emulators.dart';
import 'android_session_screen.dart';
import 'library.dart';
import 'update_screen.dart';
import '../updates/installation.dart';
import '../session_lease.dart';
import 'quit_dialog.dart';
import 'session_recovery_dialog.dart';

class BroommApp extends StatefulWidget {
  const BroommApp({
    super.key,
    required this.model,
    this.project,
    this.sessionFactory,
  });
  final ShellModel model;
  final String? project;
  final GameSession Function(Future<ResolvedSession> Function(LaunchGame))?
  sessionFactory;
  @override
  State<BroommApp> createState() => _BroommAppState();
}

class _BroommAppState extends State<BroommApp> {
  final navigator = GlobalKey<NavigatorState>();
  final homeScreen = GlobalKey<HomeScreenState>();
  late final input = ShellControllerInput(dispatch: _dispatch);
  ShellModel get m => widget.model;
  bool lab = false;
  PrototypeModel? _activeGameModel;
  bool startingGame = false;
  SessionLease? _updateLease;
  Future<void>? _quitting;

  Future<void> _requestClose() {
    if (_quitting case final work?) return work;
    if (!mounted) return Future.value();
    final context = navigator.currentContext;
    if (context == null) return Future.value();
    m.closing = true;
    final work = showQuitDialog(
      context,
      finish: (phase) async {
        m.cancelDownload();
        m.cloud.cancel();
        final active = _activeGameModel;
        if (active != null) {
          phase('Stopping the game and keeping local progress…');
          await active.stop();
          if (active.session.running || active.session.preparing)
            throw StateError(active.error ?? 'The emulator is still open.');
        }
        if (m.applicationUpdating && !m.updates.handedOff) {
          phase('Stopping the application download…');
          await m.updates.finish();
        }
        phase('Finishing emulator launch…');
        await m.finishConfiguration();
        phase('Finishing cloud saves…');
        await m.finishCloud();
        phase('Stopping emulator setup…');
        await m.emulators.finishSetup();
        phase('Keeping the download queue…');
        await m.finishDownloads();
        m.client?.close();
        phase('Closing logs…');
        await m.log?.close();
      },
      exit: DesktopHost().close,
    );
    _quitting = work;
    return work.whenComplete(() {
      if (identical(_quitting, work)) _quitting = null;
      m.closing = false;
    });
  }

  Future<void> _installApplicationUpdate() async {
    if (m.applicationUpdating || m.updates.handedOff) return;
    if (lab || m.gameActive || startingGame) {
      m.updates.status = 'Close the game or emulator before updating Broomm.';
      m.updates.emit();
      return;
    }
    m.applicationUpdating = true;
    m.busy = true;
    try {
      await m.updates.install(
        m.storage.directory,
        quiesce: () async {
          if (m.isAndroid && await m.androidSession.pending() != null)
            throw StateError(
              'Finish the Android game session before updating.',
            );
          await m.finishConfiguration();
          await m.finishCloud();
          await m.emulators.finishSetup();
          await m.finishDownloads(requireCheckpoint: true);
          _updateLease = await SessionLease.acquire(m.storage.directory);
        },
        exit: () async {
          m.log?.write(
            'Application update prepared; closing for verified installer handoff.',
          );
          await m.log?.flush().timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
          if (Platform.isMacOS) {
            await DesktopHost().close();
          } else if (await ServicesBinding.instance.exitApplication(
                AppExitType.required,
              ) ==
              AppExitResponse.cancel) {
            throw StateError(
              'The operating system cancelled application exit.',
            );
          }
        },
      );
    } finally {
      if (!m.updates.handedOff || m.isAndroid) {
        await _updateLease?.release();
        _updateLease = null;
        m.applicationUpdating = false;
        m.busy = false;
        m.updates.emit();
        if (m.authenticated) await m.loadDownloads();
      }
    }
  }

  final contentFocus = FocusScopeNode(
    debugLabel: 'Main content',
    traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );
  final homeFocus = FocusNode(debugLabel: 'Footer Home');
  final profileFocus = FocusNode(debugLabel: 'Footer profile');

  bool footerDirection(TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.up:
        contentFocus.requestFocus();
      case TraversalDirection.left:
        requestConsoleFocus(homeFocus);
      case TraversalDirection.right:
        requestConsoleFocus(profileFocus);
      case TraversalDirection.down:
        break;
    }
    return true;
  }

  Widget _footer(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 17),
      child: ConsoleDirections(
        onDirection: footerDirection,
        child: Row(
          children: [
            if (m.authenticated) ...[
              ConsoleButton(
                focusNode: homeFocus,
                label: 'Home',
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onPressed: () => m.navigate(ShellScreen.home),
                child: const Icon(Icons.home_outlined, size: 20),
              ),
              const SizedBox(width: 20),
            ],
            if (width > 650) ...[
              const _Hint('A', 'Select'),
              const SizedBox(width: 18),
              const _Hint('B', 'Back'),
              const SizedBox(width: 18),
              if (m.authenticated) const _Hint('X', 'Search'),
            ],
            const Spacer(),
            if (m.busy)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (m.authenticated) ...[
              if (width > 850) ...[
                const Text(
                  'YOUR GAMES, TOGETHER.',
                  style: TextStyle(
                    color: muted,
                    fontSize: 9,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(width: 22),
              ],
              ConsoleButton(
                key: const ValueKey('shell-profile'),
                focusNode: profileFocus,
                fill: const Color(0xff1b2935),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                onPressed: m.switchAccount,
                label: 'Switch profile',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xff49746d),
                      child: Text(
                        m.profile!.name.characters.first.toUpperCase(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: width > 650 ? 160 : 130,
                      ),
                      child: Text(
                        m.profile!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _playGame(int id) async {
    if (startingGame ||
        lab ||
        m.busy ||
        m.applicationUpdating ||
        m.gameActive ||
        !m.authenticated)
      return;
    if (m.queuedGame(id)?.state == DownloadState.active) {
      m.showNotice(
        'This game is still being installed. Wait for its download and updates/DLC to finish.',
      );
      return;
    }
    startingGame = true;
    m.gameActive = true;
    try {
      await m.finishCloud();
      if (_quitting != null) return;
      if (!m.isAndroid &&
          !await recoverGameSession(
            navigator.currentContext!,
            m.storage.directory.path,
          ))
        return;
      if (_quitting != null) return;
      if (m.isAndroid && await m.androidSession.pending() != null) {
        await _recoverAndroidSession();
        return;
      }
      final entry = m.installation(id);
      if (entry == null || entry.problem != null)
        throw StateError(
          entry?.problem ?? 'Download this game before playing.',
        );
      final platform = m.launchPlatform(entry.game);
      if (platform == null)
        throw StateError(
          'This platform does not have a tested emulator integration yet.',
        );
      if (navigator.currentState!.canPop()) navigator.currentState!.pop();
      if (!m.emulatorReady(platform) ||
          (!m.isAndroid &&
              !{'ps3', 'switch'}.contains(platform.slug) &&
              m.emulators.resourceProblems[platform.emulatorId] != null)) {
        m.gameActive = false;
        m.setupPlatformId = entry.game.platformId;
        m.navigate(ShellScreen.emulators);
        if (m.isAndroid) {
          await m.android.load();
        } else {
          await m.emulators.readPlan(only: {platform.emulatorId});
        }
        return;
      }
      final files = gameCandidates(
        platform,
        await m.library.contentFiles(entry, excludeAddons: true),
      );
      if (files.isEmpty)
        throw StateError(
          'No supported game entry was found. ${platform.slug == 'ps3' ? 'RPCS3 needs a PS3 ISO or extracted PS3_GAME/USRDIR/EBOOT.BIN.' : 'Supported files: ${platform.extensions.join(', ')}. Packed game folders must be extracted before adding them to RomM.'}',
        );
      String? selected = files.length == 1
          ? files.single
          : await showConsoleDialog<String>(
              context: navigator.currentContext!,
              builder: (context) => Dialog(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 600,
                    maxHeight: 500,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Choose a game file',
                          style: TextStyle(fontSize: 26),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView(
                            children: [
                              for (var i = 0; i < files.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: ConsoleButton(
                                    autofocus: i == 0,
                                    onPressed: () =>
                                        Navigator.pop(context, files[i]),
                                    child: Text(
                                      files[i].substring(
                                        '${entry.directory.path}/content/'
                                            .length,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ConsoleButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
      if (selected == null) return;
      if (_quitting != null) return;
      if (m.isAndroid) {
        await _playAndroid(entry, platform, selected);
        return;
      }
      final profile = m.profile!;
      final serverId = m.server!.id;
      final game = launchDescriptor(entry.game, platform, selected);
      CloudGame? cloudGame;
      late final PrototypeModel model;
      late final GameSession session;
      Future<ResolvedSession> resolve(LaunchGame g) async {
        final cancellation = session.cancellation;
        if (platform.slug == 'ps3') {
          await ensurePs3Firmware(
            m.emulators,
            profile.id,
            entry.game.platformId,
            m.client!,
            cancellation,
            (phase) {
              model.notice = phase;
              model.notifyListeners();
              m.log?.write(phase);
            },
            lease: session.ownerLease,
            emulator: platform.emulator,
          );
        }
        if (platform.slug == 'switch') {
          await ensureSwitchFirmware(
            m.emulators,
            profile.id,
            entry.game.platformId,
            m.client!,
            cancellation,
            (phase) {
              model.notice = phase;
              model.notifyListeners();
              m.log?.write(phase);
            },
            lease: session.ownerLease,
            emulator: platform.emulator,
          );
        }
        var resolved = await m.emulators.resolve(g, profile.id);
        cancellation.check();
        if (platform.slug == 'switch')
          resolved = resolved.withInstallationIdentity(
            await m.library.installationIdentity(entry, resolved.rom),
          );
        if (platform.slug == 'psx' || platform.slug == 'ps2') {
          await ensurePlayStationFirmware(
            resolved,
            entry.game.platformId,
            m.client!,
            cancellation,
            (phase) {
              model.notice = phase;
              model.notifyListeners();
              m.log?.write(phase);
            },
          );
        }
        if (g.retroCore != null) {
          await ensureRetroFirmware(
            m.emulators,
            resolved,
            entry.game.platformId,
            m.client!,
            cancellation,
            (phase) {
              model.notice = phase;
              model.notifyListeners();
              m.log?.write(phase);
            },
          );
        }
        if (platform.slug == '3ds') {
          await m.addons.applyForLaunch(
            serverId,
            entry.game.id,
            profile.id,
            Directory(resolved.emulator.root),
            resolved.rom,
          );
        }
        if (platform.slug == 'ps3')
          await m.ps3Addons.applyForLaunch(serverId, entry.game.id, profile.id);
        if ({'wii', 'switch', 'psp'}.contains(platform.slug)) {
          final packages = platform.slug == 'wii'
              ? m.wiiPackages
              : platform.slug == 'psp'
              ? m.pspPackages
              : m.switchPackagesFor(entry.game);
          if (await packages.needsSwitchSelection(serverId, entry)) {
            model.notice =
                'Preparing updates and DLC for ${platform.emulator}…';
            model.notifyListeners();
            await packages.sync(
              serverId: serverId,
              profileId: profile.id,
              entry: entry,
              game: entry.game,
              client: m.client!,
              cancellation: cancellation,
              owner: session.ownerLease,
              progress: (value) {
                model.notice = value.phase;
                model.notifyListeners();
              },
            );
          }
          await packages.applyForLaunch(
            serverId,
            entry.game.id,
            profile.id,
            Directory(resolved.emulator.root),
            resolved.rom,
            entry: entry,
          );
        }
        cancellation.check();

        try {
          try {
            cloudGame = await m.cloudGame(
              id,
              resolved: resolved,
              cancellation: cancellation,
            );
          } on SwitchNeedsInitialization catch (needed) {
            model.notice =
                'Initializing this game’s private Switch save storage…';
            model.notifyListeners();
            final program = await session.initializeSwitchStorage(resolved, g);
            await recordRyubingGame(
              resolved,
              program,
              needed.identity,
              cancellation: cancellation,
            );
            cloudGame = await m.cloudGame(
              id,
              resolved: resolved,
              cancellation: cancellation,
            );
          }
        } on UnsupportedError catch (e) {
          m.showNotice('${e.message}', problem: true);
        }
        cancellation.check();
        if (cloudGame != null) {
          model.notice = 'Checking the current profile’s broomm cloud save…';
          model.notifyListeners();
          await m.cloud.beforePlay(
            cloudGame!,
            resolve: (conflict) =>
                resolveCloudConflict(navigator.currentContext!, conflict),
          );
        }
        return resolved;
      }

      session =
          widget.sessionFactory?.call(resolve) ??
          GameSession(
            widget.project ?? '',
            managedRoot: m.storage.directory.path,
            resolve: resolve,
          );
      session.finalizeProgress = (exit) async {
        try {
          if (cloudGame != null) await m.cloud.afterPlay(cloudGame!, exit);
        } catch (e) {
          m.reportProblem(
            'Progress remains on this device. ${progressFailure(e)}',
          );
          rethrow;
        }
      };
      session.cancelProgressTransfer = m.cloud.cancel;
      model = PrototypeModel(widget.project ?? '', gameSession: session)
        ..screen = Screen.loading
        ..loadingGame = game
        ..notice = 'Preparing your private emulator profile…';
      lab = true;
      _activeGameModel = model;
      try {
        await navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => GameSessionScreen(
              model: model,
              game: game,
              launcherController: _dispatch,
              closeRequested: _requestClose,
              beforeClose: () async {
                await m.emulators.finishSetup();
                await m.finishDownloads();
                await m.finishCloud();
              },
            ),
          ),
        );
        if (model.error != null) m.reportProblem(model.error!);
      } finally {
        model.dispose();
        _activeGameModel = null;
        lab = false;
        _bind();
      }
    } catch (e) {
      m.reportProblem('$e');
    } finally {
      m.gameActive = false;
      startingGame = false;
      _scheduleArtwork();
      unawaited(m.refreshCloudStatus());
    }
  }

  Future<void> _playAndroid(
    InstalledGame entry,
    GamePlatform platform,
    String selected,
  ) async {
    final emulator = androidEmulators.singleWhere(
      (e) => e.id == platform.emulatorId,
    );
    final app = m.android.app(emulator);
    if (app == null)
      throw StateError('Install ${emulator.name} in Emulator Settings first.');
    final profile = m.profile!, server = m.server!;
    final cloudReady =
        m.android.tree(profile.id, emulator) != null &&
        m.android.progressSupported(emulator);
    await navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => AndroidSessionScreen(
          session: m.androidSession,
          title: entry.game.name,
          emulator: emulator.name,
          cloudReady: cloudReady,
          start: () async {
            final files = await m.library.contentFiles(
              entry,
              excludeAddons: true,
            );
            await m.androidSession.start(
              server: server.id,
              profile: profile.id,
              rom: entry.game.id,
              emulator: emulator,
              app: app,
              files: files,
              selected: selected,
              core:
                  platform.retroCore ??
                  (platform.slug == 'snes' ? 'snes9x' : null),
              prepare: () async {
                if (!cloudReady) return null;
                if (platform.slug == 'psp') {
                  await m.pspPackages.applyForLaunch(
                    server.id,
                    entry.game.id,
                    profile.id,
                    await m.android.privateRoot(profile.id, emulator),
                    selected,
                    entry: entry,
                  );
                }
                return m.cloudGame(entry.game.id, androidRom: selected);
              },
              resolve: (conflict) =>
                  resolveCloudConflict(navigator.currentContext!, conflict),
            );
          },
          resume: () => m.android.open(emulator),
          finish: () async => m.androidSession.finish(
            emulatorClosed: true,
            recovery: cloudReady
                ? await m.cloudGame(entry.game.id, androidRom: selected)
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _recoverAndroidSession() async {
    final record = await m.androidSession.pending();
    if (record == null) return;
    final emulator = androidEmulators.singleWhere(
      (e) => e.id == record['emulator'],
    );
    final entry = m.installation(record['rom'] as int);
    await navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => AndroidSessionScreen(
          session: m.androidSession,
          recovering: true,
          title: entry?.game.name ?? 'Unfinished Android game session',
          emulator: emulator.name,
          resume: m.android.app(emulator) == null
              ? null
              : () => m.android.open(emulator),
          finish: () async {
            CloudGame? game;
            if (m.server?.id == record['server'] &&
                m.profile?.id == record['profile'] &&
                entry != null &&
                m.android.tree(m.profile!.id, emulator) != null &&
                m.android.progressSupported(emulator)) {
              game = await m.cloudGame(
                entry.game.id,
                androidRom: record['selected'] as String?,
              );
            }
            await m.androidSession.finish(emulatorClosed: true, recovery: game);
          },
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _bind();
    input.start();
    if (m.isAndroid)
      updateChannel.setMethodCallHandler((call) async {
        if (call.method == 'installerReturned')
          m.updates.androidInstallerReturned();
      });
    m.addListener(_scheduleArtwork);
    _scheduleArtwork();
    cloudRetry = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(m.retryCloud()),
    );
  }

  bool artworkScheduled = false, showingArtwork = false, showingOptions = false;
  Timer? cloudRetry;
  void _scheduleArtwork() {
    if (artworkScheduled ||
        showingArtwork ||
        showingOptions ||
        m.artworkRequests.isEmpty ||
        lab ||
        m.gameActive ||
        m.closing ||
        m.applicationUpdating ||
        !mounted)
      return;
    artworkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      artworkScheduled = false;
      if (!mounted ||
          showingArtwork ||
          showingOptions ||
          m.artworkRequests.isEmpty ||
          lab ||
          m.applicationUpdating ||
          m.gameActive)
        return;
      final context = navigator.currentContext;
      if (context == null) return;
      showingArtwork = true;
      try {
        while (mounted &&
            m.artworkRequests.isNotEmpty &&
            m.authenticated &&
            !m.applicationUpdating &&
            !m.gameActive) {
          final game = m.artworkRequests.removeFirst();
          await selectGameArtwork(context, m, game);
        }
      } finally {
        showingArtwork = false;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _gameOptions() async {
    if (lab ||
        showingArtwork ||
        showingOptions ||
        m.busy ||
        m.gameActive ||
        m.screen != ShellScreen.home ||
        (navigator.currentState?.canPop() ?? true))
      return;
    final index = m.homeIndex - m.homeAppCount;
    if (index < 0 || index >= m.installed.length) return;
    final game = m.installed[index].game, revision = m.contextRevision;
    showingOptions = true;
    try {
      homeScreen.currentState?.focusSelection();
      await Future<void>.delayed(Duration.zero);
      if (!mounted ||
          revision != m.contextRevision ||
          (navigator.currentState?.canPop() ?? true))
        return;
      if (!m.isAndroid &&
          !await recoverGameSession(
            navigator.currentContext!,
            m.storage.directory.path,
          ))
        return;
      await homeGameOptions(navigator.currentContext!, m, game);
    } finally {
      showingOptions = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            m.screen == ShellScreen.home &&
            !(navigator.currentState?.canPop() ?? true))
          homeScreen.currentState?.focusSelection();
      });
      _scheduleArtwork();
    }
  }

  void _bind() {
    DesktopHost.channel.setMethodCallHandler((call) async {
      if (call.method == 'controller' && !lab)
        _dispatch(call.arguments as String);
      if (call.method == 'closeRequested' && !lab) {
        unawaited(_requestClose());
        return true;
      }
    });
  }

  void _dispatch(String value) {
    if (lab &&
        _quitting == null &&
        (_activeGameModel?.screen != Screen.loading ||
            _activeGameModel!.session.running))
      return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final context =
        FocusManager.instance.primaryFocus?.context ?? navigator.currentContext;
    if (context == null) return;
    if (ConsoleKeyboardHost.controller(context, value)) return;
    final Intent? intent = switch (value) {
      'up' => const ControllerDirectionIntent(TraversalDirection.up),
      'down' => const ControllerDirectionIntent(TraversalDirection.down),
      'left' => const ControllerDirectionIntent(TraversalDirection.left),
      'right' => const ControllerDirectionIntent(TraversalDirection.right),
      'accept' => const ControllerActivateIntent(),
      'back' => const BackIntent(),
      'home' => const HomeIntent(),
      'search' => const SearchIntent(),
      'options' => const GameOptionsIntent(),
      _ => null,
    };
    if (intent != null) Actions.maybeInvoke(context, intent);
  }

  void _back() {
    if (m.applicationUpdating) {
      if (!m.updates.handedOff) m.updates.cancel();
      return;
    }
    if (m.busy) return;
    if (navigator.currentState?.canPop() ?? false) {
      navigator.currentState!.maybePop();
      return;
    }
    m.back();
  }

  Future<void> _lab() async {
    if (widget.project == null || m.applicationUpdating || m.busy) {
      return;
    }
    lab = true;
    final prototype = PrototypeModel(widget.project!);
    try {
      await navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (context) => BroommPrototype(
            model: prototype,
            onReturn: () => Navigator.pop(context),
          ),
        ),
      );
    } finally {
      lab = false;
      _bind();
    }
  }

  @override
  void dispose() {
    cloudRetry?.cancel();
    m.removeListener(_scheduleArtwork);
    contentFocus.dispose();
    homeFocus.dispose();
    profileFocus.dispose();
    input.dispose();
    if (m.isAndroid) updateChannel.setMethodCallHandler(null);
    DesktopHost.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: m,
    builder: (context, _) => MaterialApp(
      navigatorKey: navigator,
      title: 'Broomm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xff0b141f),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: surface,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
          fontFamily: 'Helvetica Neue',
        ),
        dialogTheme: const DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: surface,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            for (final platform in TargetPlatform.values)
              platform: const ConsolePageTransitionsBuilder(),
          },
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              m.preferences.reduceMotion ||
              MediaQuery.disableAnimationsOf(context),
        ),
        child: Shortcuts(
          shortcuts: consoleShortcuts,
          child: Actions(
            actions: {
              GameOptionsIntent: CallbackAction<GameOptionsIntent>(
                onInvoke: (_) => _gameOptions(),
              ),
              ControllerActivateIntent:
                  CallbackAction<ControllerActivateIntent>(
                    onInvoke: (_) => activateConsoleFocus(),
                  ),
              PlayGameIntent: CallbackAction<PlayGameIntent>(
                onInvoke: (intent) => _playGame(intent.id),
              ),
              ControllerDirectionIntent:
                  CallbackAction<ControllerDirectionIntent>(
                    onInvoke: (intent) {
                      FocusManager.instance.primaryFocus?.focusInDirection(
                        intent.direction,
                      );
                      return null;
                    },
                  ),
              BackIntent: CallbackAction<BackIntent>(
                onInvoke: (_) {
                  _back();
                  return null;
                },
              ),
              HomeIntent: CallbackAction<HomeIntent>(
                onInvoke: (_) {
                  if (!m.applicationUpdating &&
                      !(navigator.currentState?.canPop() ?? true))
                    m.navigate(ShellScreen.home);
                  return null;
                },
              ),
              SearchIntent: CallbackAction<SearchIntent>(
                onInvoke: (_) {
                  if (!m.applicationUpdating &&
                      m.authenticated &&
                      !(navigator.currentState?.canPop() ?? true))
                    searchStore(navigator.currentContext!, m);
                  return null;
                },
              ),
            },
            child: FocusTraversalGroup(
              policy: ConsoleTraversalPolicy(),
              child: ConsoleKeyboardHost(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    ShellNotifications(model: m),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(
                      end:
                          homeColors[(m.authenticated ? m.homeIndex : 1) %
                              homeColors.length],
                    ),
                    duration: motionDuration(context),
                    curve: consoleCurve,
                    builder: (context, color, _) =>
                        CustomPaint(painter: _Atmosphere(color!)),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: HomeBackground(model: m),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: FocusScope(
                        node: contentFocus,
                        child: FocusTraversalGroup(
                          policy: ConsoleTraversalPolicy(),
                          child: ConsoleScreenTransition(
                            identity: m.screen,
                            child: switch (m.screen) {
                              ShellScreen.starting => Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 20),
                                    const Text('Opening Broomm…'),
                                    if (m.error != null)
                                      Padding(
                                        padding: const EdgeInsets.all(30),
                                        child: ProblemNotice(
                                          m.error!,
                                          retry: m.start,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              ShellScreen.servers ||
                              ShellScreen.profiles => Onboarding(model: m),
                              ShellScreen.home => HomeScreen(
                                key: homeScreen,
                                model: m,
                              ),
                              ShellScreen.store => StoreScreen(model: m),
                              ShellScreen.downloads => DownloadsScreen(
                                model: m,
                              ),
                              ShellScreen.update => UpdateScreen(
                                model: m,
                                install: _installApplicationUpdate,
                              ),
                              ShellScreen.settings => SettingsScreen(
                                model: m,
                                openLab: _lab,
                              ),
                              ShellScreen.emulators => EmulatorSettingsScreen(
                                model: m,
                              ),
                            },
                          ),
                        ),
                      ),
                    ),
                    _footer(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.button, this.label);
  final String button, label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30),
        ),
        child: Text(
          button,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 7),
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );
}

class _Atmosphere extends CustomPainter {
  _Atmosphere(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.65, -.25),
          radius: 1.35,
          colors: [
            color.withValues(alpha: .35),
            const Color(0xff101c28),
            const Color(0xff080f19),
          ],
        ).createShader(rect),
    );
    final paint = Paint()
      ..color = accent.withValues(alpha: .055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 9; i++) {
      final y = size.height * .35 + i * 42;
      final path = Path()
        ..moveTo(size.width * .48, y)
        ..cubicTo(
          size.width * .68,
          y - size.height * .55,
          size.width * .95,
          y + size.height * .47,
          size.width * 1.2,
          y - size.height * .25,
        );
      canvas.drawPath(path, paint);
    }
    final random = math.Random(12);
    for (var i = 0; i < 65; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        random.nextDouble() * .9 + .3,
        Paint()
          ..color = Colors.white.withValues(
            alpha: .025 + random.nextDouble() * .09,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_Atmosphere old) => old.color != color;
}

String? developmentProject() {
  const compiled = String.fromEnvironment('BROOMM_PROJECT_ROOT');
  return compiled.isNotEmpty
      ? compiled
      : Platform.environment['BROOMM_PROJECT_ROOT'];
}
