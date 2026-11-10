import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import 'controls.dart';
import 'navigation.dart';
import 'model.dart';
import 'artwork.dart';
import 'library.dart';
import 'store_screen.dart';
import '../game_launch.dart';
import '../romm/models.dart';

const homeTitles = [
  'Broomm settings',
  'Game Store',
  'Emulator Settings',
  'Downloads',
  'Update Broomm',
];
const homeIcons = [
  Icons.tune_rounded,
  Icons.shopping_bag_outlined,
  Icons.memory_rounded,
  Icons.downloading_rounded,
  Icons.system_update_alt_rounded,
];
const homeColors = [
  Color(0xff6a657f),
  Color(0xff539388),
  Color(0xff566f97),
  Color(0xff497c91),
  Color(0xff3d8b73),
];
const homeScreens = [
  ShellScreen.settings,
  ShellScreen.store,
  ShellScreen.emulators,
  ShellScreen.downloads,
  ShellScreen.update,
];

String homePlatformLabel(RommGame game) {
  const labels = {
    'playstation': 'PS1',
    'playstation1': 'PS1',
    'ps1': 'PS1',
    'psx': 'PS1',
    'playstation2': 'PS2',
    'ps2': 'PS2',
    'playstation3': 'PS3',
    'ps3': 'PS3',
    'playstation4': 'PS4',
    'ps4': 'PS4',
    'playstation5': 'PS5',
    'ps5': 'PS5',
    'playstationportable': 'PSP',
    'psp': 'PSP',
    'playstationvita': 'PS Vita',
    'psvita': 'PS Vita',
    'gameboy': 'GB',
    'gb': 'GB',
    'gameboycolor': 'GBC',
    'gbc': 'GBC',
    'gameboyadvance': 'GBA',
    'gba': 'GBA',
    'gamecube': 'GC',
    'ngc': 'GC',
    'nintendoentertainmentsystem': 'NES',
    'nes': 'NES',
    'supernintendoentertainmentsystem': 'SNES',
    'supernintendo': 'SNES',
    'snes': 'SNES',
    '64': 'N64',
    'n64': 'N64',
    'ds': 'DS',
    'nds': 'DS',
    '3ds': '3DS',
    'n3ds': '3DS',
    'switch': 'Switch',
    'switch2': 'Switch 2',
    'wii': 'Wii',
    'wiiu': 'Wii U',
    'mastersystem': 'Master System',
    'segacd': 'Sega CD',
    'turbografx16': 'TG-16',
    'pcengine': 'PC Engine',
    'panasonic3do': '3DO',
    'neogeopocketcolor': 'NGPC',
  };
  String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .replaceFirst(RegExp(r'^(sony|nintendo(?!(entertainment)))'), '');
  return labels[normalize(game.platformSlug)] ??
      labels[normalize(game.platform)] ??
      game.platform;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.model, required this.focusFooter});
  final ShellModel model;
  final VoidCallback focusFooter;
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  ShellModel get model => widget.model;
  final tiles = <int, FocusNode>{};
  final system = <int, FocusNode>{};
  final rail = ScrollController(keepScrollOffset: false);
  static const _railInset = 12.0;
  static const _selectedTileScale = 1.38;
  static const _selectionDuration = Duration(milliseconds: 340);
  static const _selectionCurve = Curves.easeInOutCubic;
  late final _growth = AnimationController(
    vsync: this,
    duration: _selectionDuration,
    value: 1,
  );
  int? _selectedTile;
  Map<int, double> _startGrowth = {};
  double? _railTarget;
  double? _railStep;
  bool _userScrolling = false;
  final primary = FocusNode(debugLabel: 'Home primary action');
  final options = FocusNode(debugLabel: 'Home game options');
  int? _previousIndex;

  void focusSelection() => requestConsoleFocus(tile(model.homeIndex));
  int _tileId(int index) => index == 0 ? 0 : model.installed[index - 1].game.id;

  FocusNode tile(int index) {
    final id = _tileId(index);
    return tiles.putIfAbsent(id, () => FocusNode(debugLabel: 'Home tile $id'));
  }

  FocusNode shortcut(int app) =>
      system.putIfAbsent(app, () => FocusNode(debugLabel: homeTitles[app]));

  bool direction(TraversalDirection direction) {
    final current = FocusManager.instance.primaryFocus;
    if (current == null) return false;
    final selected = model.homeIndex.clamp(0, model.lastHomeIndex);
    final systemRow = model.systemApps.map(shortcut).toList();
    final systemIndex = systemRow.indexOf(current);
    if (systemIndex >= 0) {
      switch (direction) {
        case TraversalDirection.left:
          if (systemIndex > 0) requestConsoleFocus(systemRow[systemIndex - 1]);
        case TraversalDirection.right:
          if (systemIndex + 1 < systemRow.length)
            requestConsoleFocus(systemRow[systemIndex + 1]);
        case TraversalDirection.down:
          requestConsoleFocus(tile(selected));
        case TraversalDirection.up:
          break;
      }
      return true;
    }
    if (current == primary || current == options) {
      switch (direction) {
        case TraversalDirection.up:
          requestConsoleFocus(tile(selected));
        case TraversalDirection.right:
          if (selected > 0 && current == primary) requestConsoleFocus(options);
        case TraversalDirection.left:
          if (current == options) requestConsoleFocus(primary);
        case TraversalDirection.down:
          widget.focusFooter();
      }
      return true;
    }
    final count = model.lastHomeIndex + 1;
    final index = List.generate(count, tile).indexOf(current);
    if (index < 0) return false;
    switch (direction) {
      case TraversalDirection.down:
        requestConsoleFocus(primary.canRequestFocus ? primary : options);
      case TraversalDirection.left:
        if (index > 0) requestConsoleFocus(tile(index - 1));
      case TraversalDirection.right:
        if (index + 1 < count) requestConsoleFocus(tile(index + 1));
      case TraversalDirection.up:
        final x = current.rect.center.dx;
        final nearest = systemRow.reduce(
          (a, b) => (a.rect.center.dx - x).abs() <= (b.rect.center.dx - x).abs()
              ? a
              : b,
        );
        requestConsoleFocus(nearest);
    }
    return true;
  }

  @override
  void dispose() {
    for (final node in [...tiles.values, ...system.values, primary, options]) {
      node.dispose();
    }
    _growth.dispose();
    rail.dispose();
    super.dispose();
  }

  void openGame(BuildContext context, InstalledGame entry) {
    if (entry.removing) {
      Actions.maybeInvoke(context, const GameOptionsIntent());
    } else if (gamePlatform(entry.game, model.platforms) != null) {
      requestPlay(context, entry.game.id);
    } else {
      gameDetails(context, model, entry.game);
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = model.homeIndex.clamp(0, model.lastHomeIndex);
    final selectedNode = tile(index);
    if (_previousIndex != index && selectedNode.hasPrimaryFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && selectedNode.hasPrimaryFocus)
          revealConsoleFocus(selectedNode);
      });
    }
    _previousIndex = index;
    final installed = model.selectedHomeGame;
    final returnShortcut = model.systemApps.contains(model.homeReturnShortcut)
        ? model.homeReturnShortcut
        : null;
    final installing =
        installed != null &&
        model.queuedGame(installed.game.id)?.state == DownloadState.active;
    final logo = model.preferences.showArtwork
        ? installed?.artwork?.logo
        : null;
    final primaryLabel = installed == null
        ? 'Open'
        : installing
        ? 'Installing…'
        : installed.removing
        ? 'Finish deleting'
        : gamePlatform(installed.game, model.platforms) != null
        ? 'Play'
        : 'View game';
    final primaryText = Text(
      primaryLabel,
      style: const TextStyle(
        color: Color(0xff101923),
        fontWeight: FontWeight.w700,
      ),
    );
    return ConsoleDirections(
      onDirection: direction,
      child: LayoutBuilder(
        builder: (context, size) {
          final margin = size.maxWidth > 900 ? 44.0 : 12.0;
          final railWidth = size.maxWidth - margin * 2;
          final tileSize = math.min(
            (size.maxWidth * .12).clamp(88.0, 150.0),
            (size.maxHeight * .26).clamp(72.0, 150.0),
          );
          // Halve the previous window-edge gap while keeping room for focus.
          final previousGap =
              margin + railWidth * .27 - tileSize * _selectedTileScale / 2;
          final selectionLeft = math.max(_railInset, previousGap / 2 - margin);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConsoleScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(
                  margin + selectionLeft,
                  12,
                  consoleSideInset(size.maxWidth),
                  8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, app) in model.systemApps.indexed)
                      Padding(
                        key: ValueKey('system-app-$app'),
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
                        child: Tooltip(
                          message: homeTitles[app],
                          excludeFromSemantics: true,
                          child: ConsoleIconButton(
                            focusNode: shortcut(app),
                            autofocus: returnShortcut == app,
                            label: homeTitles[app],
                            onPressed: () => model.navigate(
                              homeScreens[app],
                              homeShortcut: app,
                            ),
                            fill: homeColors[app].withValues(alpha: .48),
                            icon: homeIcons[app],
                            showLabel: app == 0 || app == 2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: margin),
                  child: ConsoleScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (model.libraryError != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: ProblemNotice(
                              model.libraryError!,
                              retry: model.loadLibrary,
                            ),
                          ),
                        _gameRail(
                          context,
                          index,
                          tileSize,
                          railWidth,
                          selectionLeft: selectionLeft,
                          autofocus: returnShortcut == null,
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            selectionLeft,
                            logo == null ? 8 : 60,
                            _railInset,
                            18,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (installed == null)
                                const Text(
                                  'Game Store',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              if (installed != null && logo != null)
                                _HomeGameLogo(
                                  title: installed.game.name,
                                  logo: logo,
                                  scale: model.preferences.logoScale / 100,
                                ),
                              if (installed?.problem case final problem?)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    problem,
                                    style: const TextStyle(color: ink),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: installed == null ? 185 : 330,
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: ConsoleButton(
                                        focusNode: primary,
                                        fill: ink,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: primaryLabel == 'Play'
                                              ? 10
                                              : 22,
                                          vertical: 16,
                                        ),
                                        onPressed: installing
                                            ? null
                                            : () => installed == null
                                                  ? model.navigate(
                                                      ShellScreen.store,
                                                    )
                                                  : openGame(
                                                      context,
                                                      installed,
                                                    ),
                                        child: Center(
                                          child:
                                              installed != null &&
                                                  primaryLabel == 'Play' &&
                                                  model.preferences.showArtwork
                                              ? _platformPlayLabel(
                                                  installed.game,
                                                  primaryText,
                                                  model.platformIcon(
                                                    installed.game,
                                                  ),
                                                )
                                              : primaryText,
                                        ),
                                      ),
                                    ),
                                    if (installed != null) ...[
                                      const SizedBox(width: 14),
                                      Expanded(
                                        flex: 2,
                                        child: ConsoleButton(
                                          focusNode: options,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 16,
                                          ),
                                          onPressed: () => Actions.maybeInvoke(
                                            context,
                                            const GameOptionsIntent(),
                                          ),
                                          child: const ActionLabel(
                                            'Options',
                                            icon: Icons.more_horiz,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (installed != null) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  'Select / Back · right-click · Shift+F10 for options',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _growthFor(int id) {
    final progress = _selectionCurve.transform(_growth.value);
    final start = _startGrowth[id] ?? 0;
    final end = id == _selectedTile ? 1 : 0;
    return start + (end - start) * progress;
  }

  void _animateSelection(int index, double step, Duration duration) {
    final id = _tileId(index);
    if (id != _selectedTile) {
      final previous = _selectedTile;
      final active = {..._startGrowth.keys, if (previous != null) previous};
      _startGrowth = {
        for (final tile in active)
          if (_growthFor(tile) > 0) tile: _growthFor(tile),
      };
      _selectedTile = id;
      if (previous == null || duration == Duration.zero) {
        _growth.value = 1;
      } else {
        _growth.forward(from: 0);
      }
    } else if (duration == Duration.zero && _growth.isAnimating) {
      _growth.value = 1;
    }

    final target = index * step;
    final resized = _railStep != step;
    if (!resized &&
        _railTarget == target &&
        (duration != Duration.zero ||
            !rail.hasClients ||
            (rail.offset - target).abs() < .5)) {
      return;
    }
    _railStep = step;
    _railTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !rail.hasClients ||
          _railTarget != target ||
          _railStep != step)
        return;
      _alignRail(target, resized ? Duration.zero : duration);
    });
  }

  void _alignRail(double target, Duration duration) {
    final position = rail.position;
    final offset = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((offset - position.pixels).abs() < .5) {
      if (position.isScrollingNotifier.value) rail.jumpTo(offset);
      return;
    }
    if (duration == Duration.zero) {
      rail.jumpTo(offset);
    } else {
      unawaited(
        rail.animateTo(offset, duration: duration, curve: _selectionCurve),
      );
    }
  }

  bool _handleRailScroll(
    ScrollNotification event,
    double step,
    Duration duration,
  ) {
    if (event.depth != 0 || event is! UserScrollNotification) return false;
    if (event.direction != ScrollDirection.idle) {
      _userScrolling = true;
    } else if (_userScrolling) {
      _userScrolling = false;
      final selected = model.homeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !rail.hasClients ||
            _userScrolling ||
            _railStep != step ||
            model.homeIndex != selected)
          return;
        final index = (rail.offset / step).round().clamp(
          0,
          model.lastHomeIndex,
        );
        if (index == model.homeIndex) {
          _alignRail(index * step, duration);
        } else {
          requestConsoleFocus(tile(index));
          model.homeSelection(index);
        }
      });
    }
    return false;
  }

  Widget _gameRail(
    BuildContext context,
    int selected,
    double size,
    double width, {
    required double selectionLeft,
    required bool autofocus,
  }) {
    const inset = _railInset, spacing = 16.0;
    final enlarged = size * _selectedTileScale;
    final step = size + spacing;
    final anchor = selectionLeft + enlarged;
    final duration = motionDuration(context, _selectionDuration);
    _animateSelection(selected, step, duration);
    final game = model.selectedHomeGame?.game;
    final sideWidth = width - anchor - spacing - inset;
    final beside =
        game != null &&
        _HomeCaption.fitsBeside(context, game, sideWidth, enlarged - size);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: inset + enlarged + inset,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (event) =>
                      _handleRailScroll(event, step, duration),
                  child: ConsoleScrollView(
                    controller: rail,
                    scrollDirection: Axis.horizontal,
                    revealFocus: false,
                    padding: EdgeInsets.fromLTRB(
                      anchor - enlarged,
                      inset,
                      width - anchor,
                      inset,
                    ),
                    child: AnimatedBuilder(
                      animation: _growth,
                      builder: (context, _) {
                        final ids = List.generate(
                          model.lastHomeIndex + 1,
                          _tileId,
                        );
                        final growth = ids.map(_growthFor).toList();
                        // Keep the scroll extent stable during the transition,
                        // even if an item from the previous selection disappears.
                        final remaining =
                            1 - growth.fold(0.0, (sum, value) => sum + value);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < ids.length; i++)
                              _gameTile(
                                context,
                                i,
                                size + (enlarged - size) * growth[i],
                                i < ids.length - 1 ? spacing : 0,
                                autofocus: autofocus && selected == i,
                              ),
                            if (remaining > 0)
                              SizedBox(width: (enlarged - size) * remaining),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (beside)
                  Positioned(
                    left: anchor + spacing,
                    right: inset,
                    bottom: inset,
                    child: _HomeCaption(game: game),
                  ),
              ],
            ),
          ),
          if (game != null && !beside)
            Padding(
              padding: const EdgeInsets.fromLTRB(inset, 0, inset, 4),
              child: _HomeCaption(game: game),
            ),
        ],
      ),
    );
  }

  Widget _gameTile(
    BuildContext context,
    int index,
    double size,
    double spacing, {
    required bool autofocus,
  }) {
    final entry = index == 0 ? null : model.installed[index - 1];
    void showOptions() {
      model.homeSelection(index);
      Actions.maybeInvoke(context, const GameOptionsIntent());
    }

    return Padding(
      key: ValueKey(entry == null ? 'home-store' : 'home-rom-${entry.game.id}'),
      padding: EdgeInsets.only(right: spacing),
      child: MouseRegion(
        onHover: (_) => model.homeSelection(index),
        child: GestureDetector(
          onSecondaryTap: entry == null ? null : showOptions,
          onLongPress: entry == null ? null : showOptions,
          child: SizedBox.square(
            dimension: size,
            child: ConsoleButton(
              key: entry == null
                  ? const ValueKey('home-app-1')
                  : ValueKey(entry.game.id),
              focusNode: tile(index),
              autofocus: autofocus,
              onFocus: () => model.homeSelection(index),
              label: entry?.game.name ?? homeTitles[1],
              onPressed: () => entry == null
                  ? model.navigate(ShellScreen.store)
                  : openGame(context, entry),
              padding: EdgeInsets.zero,
              radius: 19,
              fill: entry == null
                  ? homeColors[1].withValues(alpha: .6)
                  : surface,
              child: entry == null
                  ? Center(
                      child: Icon(homeIcons[1], size: size * .43, color: ink),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: _TileImage(model: model, entry: entry),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeCaption extends StatelessWidget {
  const _HomeCaption({required this.game});
  final RommGame game;

  static const _badgeStyle = TextStyle(
    color: Color(0xff101923),
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );
  static const _titleStyle = TextStyle(
    fontSize: 21,
    shadows: [Shadow(color: Colors.black, blurRadius: 10)],
  );
  static const _gap = 9.0;
  static double _badgeLimit(double width) => math.min(145, width * .35);

  static bool fitsBeside(
    BuildContext context,
    RommGame game,
    double width,
    double height,
  ) {
    if (width < 120) return false;
    TextPainter measure(
      String text,
      TextStyle style, [
      double maxWidth = double.infinity,
    ]) {
      final inherited = DefaultTextStyle.of(context).style.merge(style);
      return TextPainter(
        text: TextSpan(
          text: text,
          style: MediaQuery.boldTextOf(context)
              ? inherited.copyWith(fontWeight: FontWeight.bold)
              : inherited,
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout(maxWidth: maxWidth);
    }

    final badge = measure(homePlatformLabel(game), _badgeStyle);
    final badgeWidth = math.min(_badgeLimit(width), badge.width + 16);
    badge.dispose();
    final title = measure(game.name, _titleStyle, width - badgeWidth - _gap);
    final fits =
        title.height <= math.max(height - 4, title.preferredLineHeight);
    title.dispose();
    return fits;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      key: const ValueKey('home-selected-caption'),
      builder: (context, size) => Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _badgeLimit(size.maxWidth)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  homePlatformLabel(game),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _badgeStyle,
                ),
              ),
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: Text(
              game.name,
              key: const ValueKey('home-game-title'),
              style: _titleStyle,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TileImage extends StatelessWidget {
  const _TileImage({required this.model, required this.entry});
  final ShellModel model;
  final InstalledGame entry;
  @override
  Widget build(BuildContext context) {
    final fallback = GameArtwork(model: model, game: entry.game, compact: true);
    final path = model.preferences.showArtwork ? entry.artwork?.icon : null;
    final art = path == null
        ? fallback
        : Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 360,
            errorBuilder: (_, _, _) => fallback,
          );
    final status = model.cloudStatus(entry.game.id);
    final (icon, color, label) = switch (status) {
      CloudSaveStatus.synced => (
        Icons.cloud_done_outlined,
        accent,
        'Cloud saves synced',
      ),
      CloudSaveStatus.waiting => (
        Icons.cloud_sync_outlined,
        const Color(0xffefd3aa),
        'Cloud saves waiting to sync',
      ),
      CloudSaveStatus.attention => (
        Icons.cloud_off_outlined,
        const Color(0xffffadad),
        'Cloud saves need attention',
      ),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        art,
        Positioned(
          top: 7,
          right: 7,
          child: Tooltip(
            message: label,
            child: Semantics(
              label: label,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xf0101b28),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _platformPlayLabel(
  RommGame game,
  Text label,
  Future<Uint8List?> platformIcon,
) => FutureBuilder<Uint8List?>(
  key: ValueKey((game.platformSlug, game.platformFsSlug)),
  future: platformIcon,
  builder: (context, snapshot) {
    final icon = snapshot.data;
    if (icon == null) return label;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: game.platform,
            excludeFromSemantics: true,
            child: Image.memory(
              icon,
              key: const ValueKey('home-platform-icon'),
              width: 20,
              height: 20,
              fit: BoxFit.contain,
              semanticLabel: game.platform,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 8),
          label,
        ],
      ),
    );
  },
);

class _HomeGameLogo extends StatelessWidget {
  const _HomeGameLogo({
    required this.title,
    required this.logo,
    required this.scale,
  });
  final String title, logo;
  final double scale;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: 780 * scale),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Image(
        image: ResizeImage(
          FileImage(File(logo)),
          width: 3510,
          height: 864,
          policy: ResizeImagePolicy.fit,
        ),
        key: const ValueKey('home-game-logo'),
        semanticLabel: title,
        height: 192 * scale,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    ),
  );
}
