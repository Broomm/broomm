import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../romm/client.dart';
import '../romm/models.dart';
import '../romm/transfer.dart';
import 'library.dart';
import 'storage.dart';
import '../managed_emulators.dart';
import '../game_launch.dart';
import 'credentials.dart';
import '../steamgrid.dart';
import 'steamgrid_credentials.dart';
import 'download_queue.dart';
export 'download_queue.dart';
import '../addons/service.dart';
import '../addons/ps3.dart';
import '../addons/packages.dart';
import '../addons/astris.dart';
import '../switch_firmware.dart';
import '../progress/service.dart';
import '../progress/layout.dart';
import '../progress/files.dart';
import '../progress/status.dart';
export '../progress/status.dart' show CloudSaveStatus;
import '../session.dart';
import '../emulator_configuration.dart';
import '../android/emulators.dart';
import '../android/session.dart';
import '../android/progress.dart';
import '../updates/controller.dart';

part 'cloud_model.dart';
part 'downloads_model.dart';

enum ShellScreen {
  starting,
  servers,
  profiles,
  home,
  settings,
  store,
  emulators,
  downloads,
  update,
}

class ShellNotice {
  const ShellNotice(this.id, this.message, this.problem);
  final int id;
  final String message;
  final bool problem;
}

class ShellModel extends ChangeNotifier {
  ShellModel(
    this.storage, {
    RommClient Function(Uri)? clientFactory,
    this.log,
    this.project,
    CredentialBackend? credentials,
    ManagedEmulators? emulatorManager,
    AndroidEmulators? androidManager,
    SteamGridClient Function(String)? gridFactory,
    GameAddons? gameAddons,
    ApplicationUpdates? applicationUpdates,
    EmulatorConfiguration? configurationLauncher,
  }) : clientFactory = clientFactory ?? ((uri) => RommClient(uri)),
       credentialBackend = credentials ?? PlatformCredentials(),
       _emulatorManager = emulatorManager,
       _androidManager = androidManager,
       _gameAddons = gameAddons,
       _configurationLauncher = configurationLauncher,
       gridFactory = gridFactory ?? SteamGridClient.new,
       updates = applicationUpdates ?? ApplicationUpdates() {
    updates.addListener(_updatesChanged);
  }
  final ApplicationUpdates updates;
  bool _updateCardShown = false;
  String _updatePhase = '';
  int _updateProgressBucket = -1;
  String? _updateFailure;
  bool applicationUpdating = false;
  void _updatesChanged() {
    final failure = updates.failureDiagnostic;
    if (failure != null && failure != _updateFailure) {
      log?.write(failure, level: 'error');
    }
    _updateFailure = failure;
    final phase = updates.status;
    final bucket = updates.progress == null
        ? -1
        : (updates.progress! * 10).floor();
    if (phase != _updatePhase ||
        bucket >= 0 && bucket != _updateProgressBucket) {
      log?.write(
        'Application update: $phase${bucket < 0 ? '' : ' (${bucket * 10}%)'}',
      );
      _updatePhase = phase;
      _updateProgressBucket = bucket;
    }
    final shown = updates.available != null;
    if (shown != _updateCardShown) {
      homeIndex = shown
          ? homeIndex + 1
          : (homeIndex - 1).clamp(0, lastHomeIndex);
      _updateCardShown = shown;
    }
    _emit();
  }

  List<int> get homeApps => [
    if (updates.available != null) 4,
    0,
    1,
    if (downloads.isNotEmpty) 3,
    2,
  ];
  int get downloadHomeIndex => updates.available != null ? 3 : 2;
  final SteamGridClient Function(String) gridFactory;
  late final steamGridCredentials = SteamGridCredentials(credentials);
  final artworkRequests = Queue<RommGame>();
  Future<void>? _libraryWork;
  int get contextRevision => _context;

  Future<SteamGridClient> artworkClient() async {
    final s = server, p = profile, generation = _context;
    if (s == null || p == null)
      throw const RommFailure('Choose a profile first.');
    final key = await steamGridCredentials.read(s, p);
    if (generation != _context || disposed)
      throw const RommFailure('The active profile changed.');
    if (key == null)
      throw const RommFailure(
        'Add a SteamGridDB API key in Broomm settings to choose artwork.',
      );
    return gridFactory(key);
  }

  Future<void> saveGameArtwork(
    int id, {
    ArtworkDownload? icon,
    ArtworkDownload? hero,
    ArtworkDownload? logo,
  }) async {
    if (_libraryWork != null || !authenticated || gameActive)
      throw const RommFailure('Finish the current library operation first.');
    final generation = _context, selected = server!;
    final entry = installation(id);
    if ((entry == null &&
            !downloads.any((j) => j.game.id == id && !j.addons)) ||
        entry?.removing == true)
      throw const RommFailure('The game is no longer installed.');
    final work = () async {
      final art = entry == null
          ? await library.saveDownloadArtwork(
              selected.id,
              id,
              icon: icon,
              hero: hero,
              logo: logo,
            )
          : await library.saveArtwork(
              selected.id,
              id,
              icon: icon,
              hero: hero,
              logo: logo,
            );
      if (generation != _context || disposed) return;
      ++_libraryRevision;
      installed = [
        for (final g in installed)
          if (g.game.id == id)
            InstalledGame(
              g.game,
              g.directory,
              g.userId,
              problem: g.problem,
              artwork: art,
            )
          else
            g,
      ];
      _emit();
      log?.write('Home artwork selection saved for ROM $id.');
    }();
    _libraryWork = work;
    try {
      await work;
    } finally {
      if (identical(_libraryWork, work)) _libraryWork = null;
    }
  }

  Future<bool> deleteGame(int id) async {
    if (busy ||
        _libraryWork != null ||
        downloading ||
        gameActive ||
        !authenticated)
      return false;
    if (isAndroid && await androidSession.pending() != null) {
      reportProblem(
        'Close the Android emulator and finish its session before deleting games.',
      );
      return false;
    }
    final selected = server!, generation = _context;
    busy = true;
    error = null;
    ++_libraryRevision;
    _emit();
    await finishCloud();
    final work = library.remove(
      selected.id,
      id,
      uninstallAddons: () async {
        final platform = installation(id) == null
            ? null
            : gamePlatform(installation(id)!.game, platforms)?.slug;
        if (!isAndroid && platform == '3ds')
          await addons.uninstall(selected.id, id);
        if (!isAndroid && platform == 'ps3')
          await ps3Addons.uninstall(selected.id, id);
        if (!isAndroid && platform == 'wii')
          await wiiPackages.uninstall(selected.id, id);
        if (platform == 'psp') await pspPackages.uninstall(selected.id, id);
        if (!isAndroid && platform == 'switch') {
          await switchPackages.uninstall(selected.id, id);
          await edenPackages.uninstall(selected.id, id);
          await astrisPackages.uninstall(selected.id, id);
        }
      },
    );
    _libraryWork = work;
    try {
      await work;
      if (generation != _context || disposed) return false;
      installed = installed.where((g) => g.game.id != id).toList();
      artworkRequests.removeWhere((g) => g.id == id);
      homeIndex = homeIndex.clamp(0, homeAppCount - 1 + installed.length);
      downloadMessage =
          'Game deleted from this device. Saves and save states were kept.';
      log?.write(
        'ROM $id: local game files and artwork deleted; profile progress retained.',
      );
      return true;
    } catch (e) {
      if (generation == _context && !disposed) {
        final reason = e is FileSystemException
            ? e.message
            : e is StateError
            ? '${e.message}'
            : e is RommFailure
            ? e.message
            : 'Check storage access and retry.';
        error =
            'The game could not be completely deleted. $reason Saved progress has been kept.';
        await loadLibrary();
      }
      log?.write(
        'ROM $id: local deletion incomplete; profile progress retained.',
        level: 'warning',
      );
      return false;
    } finally {
      if (identical(_libraryWork, work)) _libraryWork = null;
      if (generation == _context && !disposed) {
        busy = false;
        _emit();
      }
    }
  }

  final ManagedEmulators? _emulatorManager;
  final AndroidEmulators? _androidManager;
  final GameAddons? _gameAddons;
  final CredentialBackend credentialBackend;
  late final credentials = ProfileCredentials(
    storage.directory,
    backend: credentialBackend,
  );
  String? _credentialNotice;
  String? get credentialNotice => _credentialNotice;
  set credentialNotice(String? value) {
    if (value != null && value != _credentialNotice) _notice(value, true);
    _credentialNotice = value;
  }

  final SessionLog? log;
  final String? project;
  late final emulators =
      _emulatorManager ??
      ManagedEmulators(storage.directory, project: project, log: log);
  late final android = (_androidManager ?? AndroidEmulators(storage.directory))
    ..onInstalled = _androidInstalled
    ..phase = (message) => log?.write(message);
  Future<void> _androidInstalled(
    String serverId,
    AndroidEmulator emulator,
  ) async {
    if (!records.servers.any((s) => s.id == serverId)) return;
    records = await storage.emulatorDefaults(serverId, {
      for (final slug in emulator.platforms) slug: emulator.id,
    });
    _cloudGames.clear();
    _emit();
  }

  late final androidSession = AndroidGameSession(android, cloud);
  bool get isAndroid => android.enabled;
  List<GamePlatform> emulatorChoices(RommPlatform platform) => !isAndroid
      ? platformEmulators(platform)
      : platformEmulators(platform)
            .where(
              (p) => android.choices(platform).any((e) => e.id == p.emulatorId),
            )
            .toList();
  bool emulatorReady(GamePlatform platform) => isAndroid
      ? androidEmulators
            .where((e) => e.id == platform.emulatorId)
            .any((e) => android.app(e)?.enabled == true)
      : emulators.readyFor(platform.emulator, platform.slug);
  final ShellStorage storage;
  final RommClient Function(Uri) clientFactory;
  late final library = GameLibrary(storage.directory);
  late final cloud = CloudSaves(
    storage.directory,
    phase: (message) => log?.write('Cloud saves: $message'),
    notice: (message, problem) {
      log?.write('Cloud saves: $message', level: problem ? 'warning' : 'info');
      showNotice(message, problem: problem);
    },
  );
  Future<void>? _cloudWork;
  bool _cloudCancelled = false;
  bool get cloudBusy => _cloudWork != null;
  final Map<int, CloudGame> _cloudGames = {};
  final Map<int, CloudSaveStatus> _cloudStatus = {};
  int _cloudStatusRevision = 0;
  final _cloudIssuesShown = <String>{};
  int _cloudRetryCursor = 0;
  late final addons =
      _gameAddons ??
      GameAddons(
        storage.directory,
        library,
        prepare: emulators.prepareAzaharAddons,
        phase: (value) => log?.write(value),
      );
  late final ps3Addons = Ps3Addons(
    storage.directory,
    library,
    prepare: (profile, cancellation) => emulators.prepareRpcs3Addons(
      profile,
      cancellation,
      emulator: _ps3InstallerEmulator,
    ),
    diagnosticProblem: (message) {
      log?.write(message, level: 'warning');
      if (!disposed) showNotice(message, problem: true);
    },
  );
  late final wiiPackages = GamePackages(
    storage.directory,
    library,
    'wii',
    prepare: (profile, cancellation) =>
        emulators.preparePackages('wii', profile, cancellation),
  );
  late final switchPackages = GamePackages(
    storage.directory,
    library,
    'switch',
    prepare: (profile, cancellation) =>
        emulators.preparePackages('switch', profile, cancellation),
    provision: (profile, platform, client, cancellation, lease, phase) =>
        ensureSwitchFirmware(
          emulators,
          profile,
          platform,
          client,
          cancellation,
          (value) {
            log?.write(value);
            phase(value);
          },
          lease: lease,
        ),
  );
  late final edenPackages = GamePackages(
    storage.directory,
    library,
    'switch',
    switchEmulator: 'Eden',
    prepare: (profile, cancellation) => emulators.preparePackages(
      'switch',
      profile,
      cancellation,
      emulator: 'Eden',
    ),
    provision: (profile, platform, client, cancellation, lease, phase) =>
        ensureSwitchFirmware(
          emulators,
          profile,
          platform,
          client,
          cancellation,
          phase,
          lease: lease,
          emulator: 'Eden',
        ),
  );
  late final astrisPackages = GamePackages(
    storage.directory,
    library,
    'switch',
    switchEmulator: 'Astris',
    switchInspector: inspectAstrisPackages,
    prepare: (profile, cancellation) => emulators.preparePackages(
      'switch',
      profile,
      cancellation,
      emulator: 'Astris',
    ),
    provision: (profile, platform, client, cancellation, lease, phase) =>
        ensureSwitchFirmware(
          emulators,
          profile,
          platform,
          client,
          cancellation,
          phase,
          lease: lease,
          emulator: 'Astris',
        ),
  );
  GamePackages switchPackagesFor(RommGame game) =>
      switch (launchPlatform(game)?.emulator) {
        'Eden' => edenPackages,
        'Astris' => astrisPackages,
        _ => switchPackages,
      };
  late final pspPackages = GamePackages(
    storage.directory,
    library,
    'psp',
    prepare: (profile, cancellation) async {
      if (!isAndroid)
        return emulators.preparePackages('psp', profile, cancellation);
      cancellation.check();
      if (await androidSession.pending() != null)
        throw StateError(
          'Close the Android emulator and finish its session before installing updates/DLC.',
        );
      await android.ensureNoWriters();
      final emulator = androidEmulators.singleWhere((e) => e.id == 'ppsspp');
      if (android.tree(profile, emulator) == null)
        throw StateError(
          'Configure PPSSPP’s Broomm Memory Stick folder in Emulator Settings before installing its updates/DLC.',
        );
      return ('', await android.privateRoot(profile, emulator));
    },
  );
  String get _ps3InstallerEmulator {
    const target = RommPlatform(0, 'PlayStation 3', 'ps3', 0);
    final preferred = defaultEmulator(target);
    if (preferred == null)
      throw StateError(
        'Set up a PlayStation 3 emulator in Emulator Settings before installing its updates and DLC.',
      );
    return platformEmulators(target)
        .firstWhere((e) => e.emulatorId == preferred)
        .emulator;
  }

  Future<AddonResult> syncGameAddons({
    required String serverId,
    required String profileId,
    required InstalledGame entry,
    required RommGame game,
    required RommClient client,
    required DownloadCancellation cancellation,
    required void Function(DownloadProgress) progress,
  }) =>
      _serializedAddon(
        cancellation,
        () => gamePlatform(game, platforms)?.slug == 'ps3'
            ? ps3Addons.sync(
                serverId: serverId,
                profileId: profileId,
                entry: entry,
                game: game,
                client: client,
                cancellation: cancellation,
                progress: progress,
              )
            : {
                'wii',
                'switch',
                'psp',
              }.contains(gamePlatform(game, platforms)?.slug)
            ? (gamePlatform(game, platforms)?.slug == 'wii'
                      ? wiiPackages
                      : gamePlatform(game, platforms)?.slug == 'psp'
                      ? pspPackages
                      : switchPackagesFor(game))
                  .sync(
                    serverId: serverId,
                    profileId: profileId,
                    entry: entry,
                    game: game,
                    client: client,
                    cancellation: cancellation,
                    progress: progress,
                  )
            : addons.sync(
                serverId: serverId,
                profileId: profileId,
                entry: entry,
                game: game,
                client: client,
                cancellation: cancellation,
                progress: progress,
              ),
      ).then((result) {
        if (gamePlatform(game, platforms)?.slug == 'psp')
          _cloudGames.remove(game.id);
        return result;
      });
  List<InstalledGame> installed = [];
  String? libraryError, _downloadError, _downloadMessage;
  String? get downloadError => _downloadError;
  set downloadError(String? value) {
    if (value != null && value != _downloadError) _notice(value, true);
    _downloadError = value;
  }

  String? get downloadMessage => _downloadMessage;
  set downloadMessage(String? value) {
    if (value != null && value != _downloadMessage) _notice(value, false);
    _downloadMessage = value;
  }

  DownloadProgress? get download => downloads
      .where((j) => j.state == DownloadState.active && j.progress != null)
      .firstOrNull
      ?.progress;
  set download(DownloadProgress? value) {
    if (value != null) queuedGame(value.game.id)?.progress = value;
  }

  final _downloadCancellations = <DownloadJob, DownloadCancellation>{};
  final _downloadWorkers = <DownloadJob, Future<void>>{};
  Future<void>? _addonTail;
  Future<void>? _downloadWork;
  Future<void>? _finishingDownloads;
  final downloads = <DownloadJob>[];
  DownloadQueueStore? _queueStore;
  bool downloadsReadOnly = false;
  String? downloadQueueNotice;
  Future<void>? _queueLoading;
  Future<void>? _queueWrite;
  bool _stoppingDownloads = false;
  int _libraryRevision = 0;
  bool get downloading => _downloadWork != null;
  InstalledGame? installation(int id) =>
      installed.where((g) => g.game.id == id).firstOrNull;
  ShellScreen screen = ShellScreen.starting;
  ShellRecords records = const ShellRecords();
  SavedServer? server;
  SavedProfile? profile;
  RommClient? client;
  bool busy = false, storeBusy = false, moreBusy = false, disposed = false;
  bool closing = false;
  bool _gameActive = false;
  bool get gameActive => _gameActive;
  final EmulatorConfiguration? _configurationLauncher;
  Future<void>? _configurationWork;

  Future<void> openEmulator(String emulator) async {
    if (!authenticated ||
        closing ||
        busy ||
        gameActive ||
        emulators.busy ||
        downloading ||
        _configurationWork != null)
      return;
    final selected = profile!;
    final configuration =
        _configurationLauncher ??
        EmulatorConfiguration(storage.directory, project, log: log);
    final work = () async {
      try {
        await finishCloud();
        await configuration.start(
          () => emulators.resolveConfiguration(emulator, selected.id),
        );
        showNotice(
          'Opening $emulator. Its settings stay private to this Broomm profile.',
        );
      } catch (e) {
        reportProblem('$e');
      }
    }();
    _configurationWork = work;
    try {
      await work;
    } finally {
      if (identical(_configurationWork, work)) _configurationWork = null;
    }
  }

  Future<void> finishConfiguration() async {
    // Finish only a pending launch request. Open applications are OS-owned;
    // Broomm neither waits for nor closes them during its own shutdown.
    await _configurationWork;
  }

  set gameActive(bool value) {
    if (_gameActive == value) return;
    _gameActive = value;
    _emit();
  }

  int? setupPlatformId;
  bool platformsLoaded = false, platformsLoading = false;
  String? _error, storeError, discoveryError;
  String? get error => _error;
  set error(String? value) {
    if (value != null && value != _error) _notice(value, true);
    _error = value;
  }

  ShellNotice? notice;
  int _noticeId = 0;
  void _notice(String message, bool problem) =>
      notice = ShellNotice(++_noticeId, message, problem);
  void showNotice(String message, {bool problem = false}) {
    _notice(message, problem);
    _emit();
  }

  String search = '';
  int? platformId;
  int homeIndex = 1;
  bool controllerSearchPending = false;
  List<RommPlatform> platforms = [];
  List<RommGame> recent = [];
  RommPage? page;
  int _context = 0, _query = 0;
  final _artwork = LinkedHashMap<String, Future<Uint8List?>>();
  int _artBytes = 0;
  final _artSizes = <String, int>{};
  ShellPreferences get preferences => records.preferences;
  bool get authenticated => client != null && profile != null;
  List<SavedProfile> get knownProfiles =>
      records.profiles.where((p) => p.serverId == server?.id).toList();
  void _emit() {
    if (!disposed) notifyListeners();
  }

  void reportProblem(String message) {
    error = message;
    _emit();
  }

  Future<void> start() async {
    busy = true;
    error = null;
    _emit();
    try {
      records = await storage.load();
      updates.start(preferences.updateChannel);
      unawaited(
        updates
            .cleanup(storage.directory)
            .then((_) {
              final notice = updates.completionNotice;
              if (!disposed && notice != null)
                showNotice(notice.message, problem: notice.problem);
            })
            .catchError((Object _) {
              log?.write(
                'Old application-update staging could not be inspected; recovery files were kept.',
                level: 'warning',
              );
            }),
      );
      if (isAndroid) {
        await android.load();
      } else {
        await emulators.load();
      }
      log?.write('Loaded saved server/profile metadata; no account activated.');
      screen = ShellScreen.servers;
    } catch (_) {
      error =
          'Broomm could not read its saved settings. Your files have been kept. Check access to ${storage.directory.path}, then retry.';
      log?.write('Persistent settings could not be read.', level: 'error');
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> addServer(String address, {bool allowHttp = false}) async {
    if (busy || gameActive) return;
    busy = true;
    error = null;
    _emit();
    RommClient? check;
    try {
      final uri = normalizeServer(address);
      if (uri.scheme == 'http' && !allowHttp)
        throw const RommFailure(
          'HTTP sends credentials without encryption. Confirm that choice or use HTTPS.',
        );
      check = clientFactory(uri);
      final version = await check.checkServer();
      log?.write('Server version verified: $version.');
      records = await storage.saveServer(uri, version);
      server = records.servers.firstWhere((s) => s.address == uri.toString());
      screen = ShellScreen.profiles;
    } catch (e) {
      log?.write(
        'Server connection or metadata publication failed.',
        level: 'warning',
      );
      error = e is RommFailure ? e.message : 'The server could not be saved. Check access to Broomm settings and retry.';
    } finally {
      check?.close();
      busy = false;
      _emit();
    }
  }

  Future<void> chooseServer(SavedServer selected) async {
    if (busy || gameActive) return;
    busy = true;
    error = null;
    _emit();
    try {
      records = await storage.saveServer(
        normalizeServer(selected.address),
        selected.version,
      );
      server = records.servers.firstWhere((s) => s.id == selected.id);
      screen = ShellScreen.profiles;
    } catch (_) {
      error = 'The server selection could not be saved. Check access to Broomm settings, then retry.';
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> login(
    String username,
    String secret, {
    bool token = false,
    SavedProfile? expected,
  }) async {
    if (busy || gameActive || server == null) return false;
    final generation = ++_context;
    busy = true;
    error = null;
    _emit();
    final connection = clientFactory(normalizeServer(server!.address));
    final selectedServer = server!;
    try {
      await finishCloud();
      await connection.checkServer();
      final user = token
          ? await connection.loginToken(secret)
          : await connection.login(username.trim(), secret);
      if (expected != null && user.id != expected.userId)
        throw const RommFailure(
          'This is a different RomM account. Use Add profile to sign in to that account.',
        );
      if (generation != _context || disposed) return false;
      records = await storage.saveProfile(server!, user);
      final saved = records.profiles.firstWhere(
        (p) => p.serverId == server!.id && p.userId == user.id,
      );
      credentialNotice = null;
      var remembered = false;
      if (connection.credential != null) {
        try {
          await credentials.locked(
            saved.id,
            () => credentials.write(
              selectedServer,
              saved,
              connection.credential!,
            ),
          );
          remembered = true;
        } catch (_) {
          _credentialProblem();
        }
      }
      if (generation != _context || disposed) return false;
      await _activate(
        connection,
        selectedServer,
        saved,
        remembered: remembered,
      );
      if (connection.readOnlyLogin)
        showNotice(
          'Signed in with read access. This RomM account needs assets.write permission for cloud saves; local progress is kept.',
          problem: true,
        );
      return true;
    } catch (e) {
      log?.write(
        'Profile authentication or publication failed.',
        level: 'warning',
      );
      if (generation == _context) error = e is RommFailure ? e.message : 'Sign-in could not be completed. Your existing profiles have been preserved.';
      return false;
    } finally {
      if (!identical(client, connection)) connection.close();
      if (generation == _context) {
        busy = false;
        _emit();
        unawaited(retryCloud());
      }
    }
  }

  void _credentialProblem() {
    credentialNotice = 'You are signed in for this session, but the saved sign-in could not be updated. Unlock your system keyring and sign in again to remember it.';
    log?.write(
      'Secure sign-in publication failed; current session retained.',
      level: 'warning',
    );
    _emit();
  }

  Future<void> _activate(
    RommClient connection,
    SavedServer selectedServer,
    SavedProfile saved, {
    required bool remembered,
  }) async {
    client?.close();
    client = connection;
    profile = saved;
    if (remembered) {
      connection.refreshGuard = (update) =>
          credentials.locked(saved.id, () async {
            if (!identical(client, connection) || disposed)
              throw const RommFailure('This profile connection has closed.');
            final latest = await credentials.read(selectedServer, saved);
            if (latest == null)
              throw const RommFailure(
                'The saved sign-in was removed. Sign in again.',
                status: 401,
              );
            await update(latest);
          });
      connection.onCredentialChanged = (value) async {
        if (!identical(client, connection) || disposed) return;
        try {
          await credentials.write(selectedServer, saved, value);
        } catch (_) {
          if (!identical(client, connection) || disposed) return;
          connection.refreshGuard = null;
          connection.onCredentialChanged = null;
          _credentialProblem();
        }
      };
    }
    log?.write('Authenticated profile activated; catalogue context replaced.');
    _clearCatalogue();
    screen = ShellScreen.home;
    _emit();
    await loadLibrary();
    await loadDownloads();
    unawaited(loadStore());
  }

  /// true: restored; false: no reusable/accepted credential; null: uncertain
  /// storage/network failure, so keep the chooser without a password prompt.
  Future<bool?> activateProfile(SavedProfile saved) async {
    if (busy || gameActive || server == null || saved.serverId != server!.id)
      return null;
    final generation = ++_context, selectedServer = server!;
    busy = true;
    error = credentialNotice = null;
    _emit();
    final connection = clientFactory(normalizeServer(selectedServer.address));
    var remembered = true;
    try {
      await finishCloud();
      final restored = await credentials.locked(saved.id, () async {
        final value = await credentials.read(selectedServer, saved);
        if (value == null) return false;
        await connection.checkServer();
        final user = await connection.restore(value);
        if (user.id != saved.userId)
          throw const CredentialFailure(
            'The saved sign-in identifies a different account. Existing profiles have been kept.',
          );
        if (generation != _context || disposed) return false;
        records = await storage.saveProfile(selectedServer, user);
        if (connection.credential != null) {
          try {
            await credentials.write(
              selectedServer,
              saved,
              connection.credential!,
            );
          } catch (_) {
            remembered = false;
            _credentialProblem();
          }
        }
        return true;
      });
      if (generation != _context || disposed) return null;
      if (!restored) return false;
      final selected = records.profiles.firstWhere((p) => p.id == saved.id);
      await _activate(
        connection,
        selectedServer,
        selected,
        remembered: remembered,
      );
      return true;
    } on RommFailure catch (e) {
      if (generation == _context) error = e.message;
      if (e.status == 401) return false;
      return null;
    } on CredentialFailure catch (e) {
      if (generation == _context) error = e.message;
      return null;
    } catch (_) {
      if (generation == _context) error = 'The saved sign-in could not be restored. Existing profiles and credentials have been kept.';
      return null;
    } finally {
      if (!identical(client, connection)) connection.close();
      if (generation == _context) {
        busy = false;
        _emit();
        unawaited(retryCloud());
      }
    }
  }

  Future<void> signOut() async {
    if (busy || gameActive || profile == null) return;
    final saved = profile!;
    busy = true;
    error = null;
    _emit();
    try {
      await finishCloud();
      if (client?.credential != null)
        await credentials.locked(saved.id, () => credentials.delete(saved.id));
      busy = false;
      switchAccount();
    } catch (_) {
      error = 'The saved sign-in could not be removed. Unlock your system keyring and retry signing out.';
    } finally {
      busy = false;
      _emit();
    }
  }

  void navigate(ShellScreen target) {
    if (busy || applicationUpdating || gameActive || !authenticated) return;
    error = null;
    screen = target;
    _emit();
  }

  void homeSelection(int index) {
    if (homeIndex != index) {
      homeIndex = index;
      _emit();
    }
  }

  void switchAccount() {
    if (busy || gameActive) return;
    if (_downloadWork != null ||
        _queueWrite != null ||
        _queueStore != null ||
        _queueLoading != null ||
        downloadsReadOnly ||
        downloads.isNotEmpty) {
      unawaited(finishDownloads().then((_) => switchAccount()));
      return;
    }
    if (_cloudWork != null) {
      final generation = _context;
      unawaited(
        finishCloud().then((_) {
          if (generation == _context) switchAccount();
        }),
      );
      return;
    }
    ++_context;
    ++_query;
    cancelDownload();
    client?.close();
    log?.write(
      'Profile deactivated; pending HTTP work cancelled and saved sign-in retained.',
    );
    client = null;
    profile = null;
    credentialNotice = null;
    _clearCatalogue();
    installed = [];
    libraryError = downloadError = downloadMessage = null;
    download = null;
    homeIndex = 1;
    screen = ShellScreen.profiles;
    error = null;
    _emit();
  }

  void changeServer() {
    if (busy || gameActive) return;
    if (_downloadWork != null ||
        _queueWrite != null ||
        _queueStore != null ||
        _queueLoading != null ||
        downloadsReadOnly ||
        downloads.isNotEmpty) {
      unawaited(finishDownloads().then((_) => changeServer()));
      return;
    }
    if (_cloudWork != null) {
      final generation = _context;
      unawaited(
        finishCloud().then((_) {
          if (generation == _context) changeServer();
        }),
      );
      return;
    }
    if (authenticated) switchAccount();
    server = null;
    screen = ShellScreen.servers;
    error = null;
    _emit();
  }

  void back() {
    if (busy) return;
    if (screen == ShellScreen.profiles) {
      changeServer();
      return;
    }
    if (screen != ShellScreen.home && authenticated) navigate(ShellScreen.home);
  }

  void _clearCatalogue() {
    _cloudGames.clear();
    _cloudStatus.clear();
    ++_cloudStatusRevision;
    _cloudIssuesShown.clear();
    _cloudRetryCursor = 0;
    notice = null;
    artworkRequests.clear();
    platforms = [];
    platformsLoaded = false;
    platformsLoading = false;
    setupPlatformId = null;
    recent = [];
    page = null;
    search = '';
    platformId = null;
    storeError = null;
    discoveryError = null;
    _hasMore = null;
    _nextOffset = 0;
    storeBusy = false;
    moreBusy = false;
    _artwork.clear();
    _artSizes.clear();
    _artBytes = 0;
  }

  Future<void> loadStore() async {
    final connection = client;
    if (connection == null) return;
    final generation = _context;
    discoveryError = null;
    storeBusy = true;
    _emit();
    // Failure to inspect platforms must not masquerade as a server with none.
    await refreshPlatforms();
    if (generation != _context) return;
    try {
      final values = await connection.games(limit: 10, recent: true);
      if (generation == _context) {
        recent = values.games;
        _emit();
      }
    } catch (e) {
      if (generation == _context) {
        discoveryError = 'Store picks could not be loaded: $e';
        _emit();
      }
    }
    if (generation == _context) await browse();
  }

  Future<void> refreshPlatforms() async {
    final connection = client, generation = _context;
    if (connection == null) return;
    platformsLoading = true;
    discoveryError = null;
    _emit();
    try {
      final values = await connection.platforms();
      if (generation != _context) return;
      platforms = values;
      platformsLoaded = true;
    } catch (e) {
      if (generation == _context)
        discoveryError = 'Platforms could not be loaded: $e';
    } finally {
      if (generation == _context) {
        platformsLoading = false;
        _emit();
      }
    }
  }

  String? defaultEmulator(RommPlatform platform) {
    final choices = emulatorChoices(platform);
    if (choices.isEmpty) return null;
    final preferred =
        records.emulatorDefaults['${server?.id}:${choices.first.slug}'];
    final configured = choices.where(emulatorReady).toList();
    if (configured.isEmpty) return null;
    return configured
            .where((p) => p.emulatorId == preferred)
            .firstOrNull
            ?.emulatorId ??
        configured.first.emulatorId;
  }

  Future<void> setupEmulators(SetupPlan plan) async {
    final selectedServer = server;
    if (selectedServer == null || gameActive || busy || emulators.busy) return;
    await finishCloud();
    await emulators.install(
      plan,
      onInstalled: (build) async {
        final choices = {
          for (final platform in playablePlatforms)
            if (platform.emulatorId == build.id && emulatorReady(platform))
              platform.slug: build.id,
        };
        if (choices.isEmpty) return;
        try {
          final saved = await storage.emulatorDefaults(
            selectedServer.id,
            choices,
          );
          if (!disposed) {
            records = saved;
            _cloudGames.clear();
            _emit();
          }
        } catch (_) {
          throw StateError(
            '${build.name} was installed, but its default selection could not be saved. Use Set as default to retry.',
          );
        }
      },
    );
    unawaited(retryCloud());
  }

  GamePlatform? launchPlatform(RommGame game) {
    final platform =
        platforms.where((p) => p.id == game.platformId).firstOrNull ??
        RommPlatform(game.platformId, game.platform, game.platformSlug, 0);
    final options = emulatorChoices(platform);
    final preferred = defaultEmulator(platform);
    return options.where((p) => p.emulatorId == preferred).firstOrNull ??
        (isAndroid ? null : gamePlatform(game, platforms));
  }

  Future<void> setDefaultEmulator(
    RommPlatform platform,
    String emulator,
  ) async {
    if (busy || gameActive || server == null) return;
    final choices = emulatorChoices(platform);
    if (!choices.any((p) => p.emulatorId == emulator && emulatorReady(p))) {
      reportProblem(
        'Set up a supported emulator before making it the default.',
      );
      return;
    }
    try {
      if (isAndroid) await android.cancelInstallationDefault(server!.id);
      records = await storage.emulatorDefault(
        server!.id,
        choices.first.slug,
        emulator,
      );
      // Ordinary PS2 cards are shared, but a cached CloudGame can still name
      // the previous emulator's state group. Resolve the new default afresh.
      _cloudGames.clear();
      _emit();
    } catch (_) {
      reportProblem(
        'The default emulator could not be saved. Your previous selection has been kept.',
      );
    }
  }

  Future<void> browse({
    String? term,
    int? platform,
    bool clearPlatform = false,
  }) async {
    final connection = client;
    if (connection == null) return;
    final generation = _context, query = ++_query;
    if (term != null) search = term.trim();
    if (clearPlatform)
      platformId = null;
    else if (platform != null)
      platformId = platform;
    storeBusy = true;
    storeError = null;
    moreBusy = false;
    page = null;
    _hasMore = null;
    _nextOffset = 0;
    _emit();
    try {
      final result = await connection.games(
        search: search,
        platform: platformId,
        limit: preferences.pageSize,
      );
      if (generation == _context && query == _query) {
        page = result;
        _hasMore = result.hasMore;
        _nextOffset = result.offset + result.games.length;
      }
    } catch (e) {
      if (generation == _context && query == _query) storeError = '$e';
      log?.write('Catalogue page request failed.', level: 'warning');
    } finally {
      if (generation == _context && query == _query) {
        storeBusy = false;
        _emit();
      }
    }
  }

  Future<void> loadMore() async {
    final previous = page, connection = client;
    if (connection == null ||
        previous == null ||
        !hasMore ||
        moreBusy ||
        storeBusy)
      return;
    final generation = _context, query = _query;
    moreBusy = true;
    storeError = null;
    _emit();
    try {
      final result = await connection.games(
        search: search,
        platform: platformId,
        offset: _nextOffset,
        limit: previous.limit,
      );
      if (generation == _context && query == _query) {
        final seen = previous.games.map((g) => g.id).toSet();
        page = RommPage(
          [...previous.games, ...result.games.where((g) => seen.add(g.id))],
          result.total,
          0,
          previous.limit,
        );
        // Aggregate pages preserve the server's hasMore decision separately.
        _hasMore = result.hasMore;
        _nextOffset = result.offset + result.games.length;
      }
    } catch (e) {
      if (generation == _context && query == _query) storeError = '$e';
    } finally {
      if (generation == _context && query == _query) {
        moreBusy = false;
        _emit();
      }
    }
  }

  bool? _hasMore;
  int _nextOffset = 0;
  bool get hasMore => _hasMore ?? page?.hasMore ?? false;
  Future<RommGame> detail(RommGame game) async {
    final current = client, generation = _context;
    if (current == null) throw const RommFailure('Choose a profile first.');
    final result = await current.game(game.id);
    if (result.id != game.id)
      throw const RommFailure('RomM returned a different game identity.');
    if (generation != _context)
      throw const RommFailure('The active profile changed.');
    return result;
  }

  Future<Uint8List?> artwork(String path) {
    final existing = _artwork.remove(path);
    if (existing != null) {
      _artwork[path] = existing;
      return existing;
    }
    final generation = _context, connection = client;
    if (connection == null) return Future.value();
    final future = connection.artwork(path).catchError((Object _) => null).then(
      (bytes) {
        if (generation != _context) return null;
        if (bytes != null) {
          _artSizes[path] = bytes.length;
          _artBytes += bytes.length;
        }
        while ((_artBytes > 32 * 1024 * 1024 || _artwork.length > 64) &&
            _artwork.isNotEmpty) {
          final key = _artwork.keys.first;
          _artwork.remove(key);
          _artBytes -= _artSizes.remove(key) ?? 0;
        }
        return bytes;
      },
    );
    _artwork[path] = future;
    return future;
  }

  Future<void> loadLibrary() async {
    final revision = _libraryRevision;
    final selected = server,
        connection = client,
        active = profile,
        generation = _context;
    if (selected == null || connection == null || active == null) return;
    try {
      final snapshot = await library.load(selected.id);
      final allowed = <InstalledGame>[];
      String? problem = snapshot.problem;
      for (final entry in snapshot.games) {
        if (generation != _context || disposed) return;
        try {
          // A shared payload does not grant another account catalogue access.
          await connection.game(entry.game.id);
          allowed.add(entry);
        } catch (e) {
          if (e is RommFailure && [401, 403, 404].contains(e.status)) {
            problem = 'Some downloaded games are not accessible to this account. Their local files have been kept.';
          } else {
            if (entry.userId == active.userId) allowed.add(entry);
            problem = 'Some local games could not be checked with RomM. Your downloaded files have been kept.';
          }
        }
      }
      if (generation != _context || disposed) return;
      if (revision != _libraryRevision) return;
      installed = allowed;
      libraryError = problem;
      await refreshCloudStatus();
      unawaited(retryCloud());
    } catch (e) {
      if (generation != _context || disposed) return;
      libraryError = e is RommFailure ? e.message : 'The local game library could not be read. Existing game files have been kept. Check storage access and retry.';
    }
    _emit();
  }

  Future<void> downloadGame(RommGame game) {
    return enqueueDownload(game);
  }

  bool supportsAddons(RommGame game) =>
      (isAndroid ? ['psp'] : ['3ds', 'ps3', 'wii', 'switch', 'psp']).contains(
        gamePlatform(game, platforms)?.slug,
      );

  Future<void> downloadUpdatesAndDlc(int id) {
    if (busy || gameActive || _libraryWork != null || !authenticated)
      return Future.value();
    final entry = installation(id);
    if (entry == null || entry.removing) return Future.value();
    return enqueueDownload(entry.game, addons: true);
  }

  void Function(DownloadProgress) _addonProgress(int generation) {
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    String? phase;
    return (value) {
      if (generation != _context || disposed) return;
      final now = DateTime.now();
      if (phase == value.phase && now.difference(last).inMilliseconds < 120)
        return;
      if (phase != value.phase)
        log?.write('ROM ${value.game.id}: ${value.phase}.');
      phase = value.phase;
      last = now;
      download = value;
      _emit();
    };
  }

  Future<void> _waitForGameEnd(
    RommGame game,
    DownloadCancellation cancellation,
  ) async {
    if (!gameActive) return;
    download = DownloadProgress(
      game,
      'Waiting for the current game to close before installing add-ons',
      0,
      0,
    );
    _emit();
    while (gameActive && !disposed) {
      cancellation.check();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    cancellation.check();
  }

  String _addonFailure(Object e) => e is RommFailure
      ? e.message
      : e is StateError
      ? '${e.message}'
      : e is FormatException
      ? e.message
      : e is FileSystemException
      ? e.message
      : e is UnsupportedError
      ? '${e.message}'
      : 'Check storage access and emulator setup, then retry.';

  Future<void> _updateAddons(
    InstalledGame entry,
    DownloadCancellation cancellation,
    DownloadJob job,
  ) async {
    final generation = _context,
        selected = server!,
        active = profile!,
        connection = client!;
    downloadError = downloadMessage = null;
    download = DownloadProgress(
      entry.game,
      'Checking RomM for updates and DLC',
      0,
      0,
    );
    _emit();
    try {
      final game = await connection.game(entry.game.id);
      cancellation.check();
      await _waitForGameEnd(game, cancellation);
      final result = await syncGameAddons(
        serverId: selected.id,
        profileId: active.id,
        entry: entry,
        game: game,
        client: connection,
        cancellation: cancellation,
        progress: _addonProgress(generation),
      );
      if (generation != _context || disposed) return;
      downloadMessage = result.message;
      log?.write('ROM ${game.id}: ${result.message}');
    } catch (e) {
      if (generation != _context || disposed) return;
      job.problem = e is DownloadCancelled
          ? 'Update/DLC download cancelled. Completed installations and progress were kept.'
          : 'Updates and DLC could not be completed. ${_addonFailure(e)} Your game and progress were kept. Retry Download Updates and DLC from Options.';
      downloadError = job.problem;
      log?.write(
        'ROM ${entry.game.id}: add-on check incomplete; existing progress kept.',
        level: 'warning',
      );
    } finally {
      if (generation == _context && !disposed) {
        download = null;
        _emit();
      }
    }
  }

  Future<void> _install(
    RommGame selectedGame,
    DownloadCancellation cancellation,
    DownloadJob job,
  ) async {
    final generation = _context,
        selected = server!,
        active = profile!,
        connection = client!;
    downloadError = downloadMessage = null;
    download = DownloadProgress(
      selectedGame,
      'Preparing download',
      0,
      selectedGame.bytes,
    );
    _emit();
    log?.write('Preparing ROM download: game ${selectedGame.id}.');
    try {
      final game = await connection.game(selectedGame.id);
      cancellation.check();
      if (game.id != selectedGame.id)
        throw const RommFailure('RomM returned a different game identity.');
      // Lightweight catalogue entries can omit the mapping. Offer its picker
      // as soon as the refreshed metadata arrives, before transferring files.
      if (selectedGame.sgdbId == null && game.sgdbId != null) {
        artworkRequests.add(game);
        _emit();
      }
      if (installation(game.id) != null) {
        if (supportsAddons(game))
          await _updateAddons(installation(game.id)!, cancellation, job);
        else
          downloadMessage = '${game.name} is already downloaded.';
        return;
      }
      var last = DateTime.fromMillisecondsSinceEpoch(0);
      var lastLog = last;
      String? phase;
      final result = await library.install(
        serverId: selected.id,
        userId: active.userId,
        game: game,
        client: connection,
        cancellation: cancellation,
        verifyChecksum: preferences.verifyDownloads,
        progress: (value) {
          if (generation != _context || disposed) return;
          final now = DateTime.now();
          if (now.difference(lastLog).inSeconds >= 5) {
            log?.write(
              'ROM ${game.id}: ${value.received}/${value.total} bytes received.',
            );
            lastLog = now;
          }
          if (phase != value.phase ||
              now.difference(last).inMilliseconds >= 120 ||
              value.received == value.total) {
            if (phase != value.phase)
              log?.write('ROM ${game.id}: ${value.phase}.');
            phase = value.phase;
            last = now;
            download = value;
            _emit();
          }
        },
      );
      if (generation != _context || disposed) return;
      await _libraryWork;
      HomeArtwork? art;
      try {
        art = await library.artworkFor(
          selected.id,
          game.id,
          legacy: result.directory,
        );
      } catch (_) {
        log?.write(
          'Optional artwork could not be read for ROM ${game.id}; the verified game was kept.',
          level: 'warning',
        );
      }
      ++_libraryRevision;
      installed =
          [
            ...installed,
            InstalledGame(
              result.game,
              result.directory,
              result.userId,
              artwork: art,
            ),
          ]..sort(
            (a, b) =>
                a.game.name.toLowerCase().compareTo(b.game.name.toLowerCase()),
          );
      log?.write('ROM ${game.id}: verified download published.');
      _emit();
      if (supportsAddons(game)) {
        try {
          await _waitForGameEnd(game, cancellation);
          final added = await syncGameAddons(
            serverId: selected.id,
            profileId: active.id,
            entry: result,
            game: game,
            client: connection,
            cancellation: cancellation,
            progress: _addonProgress(generation),
          );
          if (generation == _context && !disposed)
            downloadMessage = '${game.name} downloaded. ${added.message}';
        } catch (e) {
          if (generation == _context && !disposed) {
            job.problem =
                '${game.name} is downloaded, but updates/DLC are incomplete. ${_addonFailure(e)} Retry Download Updates and DLC from Options. Progress was kept.';
            downloadError = job.problem;
          }
          log?.write(
            'ROM ${game.id}: base download retained; add-on installation incomplete.',
            level: 'warning',
          );
        }
      } else {
        downloadMessage = '${game.name} downloaded. Find it on Home.';
      }
    } catch (e) {
      if (generation != _context || disposed) return;
      if (e is DownloadCancelled) {
        downloadMessage = 'Download cancelled. Retry from the game page.';
        log?.write('ROM ${selectedGame.id}: download cancelled.');
      } else {
        job.problem = e is RommFailure ? e.message : 'The download could not be saved. Check free space and write access, then retry from the game page.';
        downloadError = job.problem;
        log?.write(
          'ROM ${selectedGame.id}: download failed; completed installations preserved.',
          level: 'warning',
        );
      }
    } finally {
      if (generation == _context) {
        download = null;
        _emit();
      }
    }
  }

  void cancelDownload([DownloadJob? job]) {
    if (job != null) {
      _downloadCancellations[job]?.cancel();
    } else {
      for (final cancellation in _downloadCancellations.values)
        cancellation.cancel();
    }
  }

  Future<void> finishDownloads({bool requireCheckpoint = false}) {
    if (_finishingDownloads case final work?) {
      if (requireCheckpoint)
        throw StateError(
          'A download shutdown is already in progress. Retry the update when it finishes.',
        );
      return work;
    }
    if (requireCheckpoint && downloadsReadOnly)
      throw StateError(
        'Quit the other Broomm instance managing downloads before updating.',
      );
    final work = _finishDownloads(requireCheckpoint: requireCheckpoint);
    _finishingDownloads = work;
    return work.whenComplete(() {
      if (identical(_finishingDownloads, work)) _finishingDownloads = null;
    });
  }

  Future<void> _finishDownloads({bool requireCheckpoint = false}) async {
    _stoppingDownloads = true;
    try {
      await _queueLoading;
      cancelDownload();
      await _downloadWork;
      await _addonTail;
      await _libraryWork;
    } catch (_) {
      /* The owning boundary reports the result. */
    }
    try {
      if (requireCheckpoint && _queueStore != null) await _saveDownloads();
      await _queueWrite;
    } catch (_) {
      downloadError = 'The last queue checkpoint could not be saved. Interrupted downloads may need a retry when you return.';
      log?.write(downloadError!, level: 'warning');
      if (requireCheckpoint) {
        _stoppingDownloads = false;
        throw StateError(
          'The download queue could not be saved. Broomm stayed open with its queue and data retained. Fix storage access and retry.',
        );
      }
    }
    try {
      await _queueStore?.close();
    } catch (_) {
      log?.write(
        'The download queue lock could not be closed cleanly.',
        level: 'error',
      );
    } finally {
      _queueStore = null;
      downloadsReadOnly = false;
      downloadQueueNotice = null;
      for (final job in downloads) {
        if (!job.done.isCompleted) job.done.complete();
      }
      downloads.clear();
      _stoppingDownloads = false;
    }
  }

  void dismissDownloadNotice() {
    downloadError = downloadMessage = null;
    _emit();
  }

  Future<void> savePreferences(ShellPreferences next) async {
    if (busy) return;
    busy = true;
    error = null;
    _emit();
    try {
      final previous = preferences;
      records = await storage.preferences(next);
      if (previous.updateChannel != next.updateChannel)
        unawaited(updates.setChannel(next.updateChannel));
      _startQueue();
      if (previous.pageSize != next.pageSize && authenticated) {
        _hasMore = null;
        unawaited(browse());
      }
    } catch (_) {
      error = 'Settings could not be saved. Your previous settings are still in use.';
    } finally {
      busy = false;
      _emit();
    }
  }

  @override
  void dispose() {
    disposed = true;
    updates.removeListener(_updatesChanged);
    updates.dispose();
    cloud.cancel();
    emulators.dispose();
    androidSession.dispose();
    android.dispose();
    ++_context;
    cancelDownload();
    unawaited(finishDownloads());
    client?.close();
    if (log != null) unawaited(log!.close());
    super.dispose();
  }
}
