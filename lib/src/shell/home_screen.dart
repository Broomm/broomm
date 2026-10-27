import 'dart:io';

import 'package:flutter/material.dart';

import 'controls.dart';
import 'navigation.dart';
import 'model.dart';
import 'artwork.dart';
import 'library.dart';
import 'store_screen.dart';
import '../game_launch.dart';

const homeTitles = [
  'Broomm settings',
  'Game Store',
  'Emulator Settings',
  'Downloads',
  'Update Broomm',
];
const homeDescriptions = [
  'Make yourself at home.\nYour display, your controls, your preferences.',
  'Your collection, rediscovered.\nFind your next adventure in RomM.',
  'Great games deserve a great setup.\nA home for your emulators.',
  'Your next games are on their way.\nManage downloads, retries and your queue.',
  'A new Broomm release is ready.\nDownload, install and restart with your library intact.',
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.model});
  final ShellModel model;
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  ShellModel get model => widget.model;
  List<int> get apps => model.homeApps;
  final tiles = <String, FocusNode>{};
  final primary = FocusNode(debugLabel: 'Home primary action');
  final options = FocusNode(debugLabel: 'Home game options');
  void focusSelection() =>
      requestConsoleFocus(tile(model.homeIndex.clamp(0, model.lastHomeIndex)));
  FocusNode tile(int index) => tiles.putIfAbsent(
    index < apps.length
        ? 'app-${apps[index]}'
        : 'game-${model.installed[index - apps.length].game.id}',
    () => FocusNode(debugLabel: 'Home tile $index'),
  );

  bool direction(TraversalDirection direction) {
    final selected = model.homeIndex.clamp(0, model.lastHomeIndex);
    final current = FocusManager.instance.primaryFocus;
    if (current == null) return false;
    if (current == primary || current == options) {
      switch (direction) {
        case TraversalDirection.up:
          requestConsoleFocus(tile(selected));
        case TraversalDirection.right:
          if (selected >= apps.length && current == primary)
            requestConsoleFocus(options);
        case TraversalDirection.left:
          if (current == options) requestConsoleFocus(primary);
        case TraversalDirection.down:
          return false;
      }
      return true;
    }
    final count = apps.length + model.installed.length;
    final index = List.generate(count, tile).indexOf(current);
    if (index < 0) return false;
    switch (direction) {
      case TraversalDirection.down:
        requestConsoleFocus(primary);
      case TraversalDirection.left:
        if (index > 0) requestConsoleFocus(tile(index - 1));
      case TraversalDirection.right:
        if (index + 1 < count) requestConsoleFocus(tile(index + 1));
      case TraversalDirection.up:
        break;
    }
    return true;
  }

  @override
  void dispose() {
    for (final node in tiles.values) {
      node.dispose();
    }
    primary.dispose();
    options.dispose();
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
    final installed = index < apps.length
        ? null
        : model.installed[index - apps.length];
    final installing =
        installed != null &&
        model.downloading &&
        model.queuedGame(installed.game.id)?.state == DownloadState.active;
    final title =
        installed?.game.name ??
        (apps[index] == 4
            ? 'Broomm ${model.updates.available!.version}'
            : homeTitles[apps[index]]);
    void open() => installed != null
        ? openGame(context, installed)
        : model.navigate(homeScreens[apps[index]]);
    return ConsoleDirections(
      onDirection: direction,
      child: LayoutBuilder(
        builder: (context, size) {
          final tileSize = (size.maxWidth * .12).clamp(108.0, 160.0);
          return ConsoleScrollView(
            padding: EdgeInsets.fromLTRB(
              size.maxWidth > 900 ? 56 : 24,
              26,
              24,
              24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (size.maxHeight - 50).clamp(0, double.infinity),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (model.libraryError != null)
                    ProblemNotice(
                      model.libraryError!,
                      retry: () => model.loadLibrary(),
                    ),
                  ConsoleScrollView(
                    scrollDirection: Axis.horizontal,
                    centerZone: .18,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        for (
                          var i = 0;
                          i < apps.length + model.installed.length;
                          i++
                        )
                          MouseRegion(
                            onEnter: (_) => model.homeSelection(i),
                            child: GestureDetector(
                              onSecondaryTap: i < apps.length
                                  ? null
                                  : () {
                                      model.homeSelection(i);
                                      Actions.maybeInvoke(
                                        context,
                                        const GameOptionsIntent(),
                                      );
                                    },
                              onLongPress: i < apps.length
                                  ? null
                                  : () {
                                      model.homeSelection(i);
                                      Actions.maybeInvoke(
                                        context,
                                        const GameOptionsIntent(),
                                      );
                                    },
                              child: Padding(
                                padding: const EdgeInsets.only(right: 18),
                                child: ConsoleButton(
                                  key: i < apps.length
                                      ? ValueKey('home-app-${apps[i]}')
                                      : ValueKey(
                                          model
                                              .installed[i - apps.length]
                                              .game
                                              .id,
                                        ),
                                  focusNode: tile(i),
                                  autofocus: i == index,
                                  onFocus: () => model.homeSelection(i),
                                  label: i < apps.length
                                      ? homeTitles[apps[i]]
                                      : model
                                            .installed[i - apps.length]
                                            .game
                                            .name,
                                  onPressed: () => i < apps.length
                                      ? model.navigate(homeScreens[apps[i]])
                                      : openGame(
                                          context,
                                          model.installed[i - apps.length],
                                        ),
                                  padding: EdgeInsets.zero,
                                  radius: 19,
                                  fill: i < apps.length
                                      ? homeColors[apps[i]].withValues(
                                          alpha: .6,
                                        )
                                      : surface,
                                  child: SizedBox(
                                    width: tileSize,
                                    height: tileSize,
                                    child: i < apps.length
                                        ? Icon(
                                            homeIcons[apps[i]],
                                            size: tileSize * .43,
                                            color: i == index
                                                ? ink
                                                : Colors.white70,
                                          )
                                        : ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: _TileImage(
                                              model: model,
                                              entry: model
                                                  .installed[i - apps.length],
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: size.maxHeight > 650 ? 72 : 42),
                  AnimatedSwitcher(
                    duration: motionDuration(context),
                    child: Align(
                      key: ValueKey(index),
                      alignment: Alignment.centerLeft,
                      child: HomeGameTitle(
                        title: title,
                        logo: model.preferences.showArtwork
                            ? installed?.artwork?.logo
                            : null,
                        wide: size.maxWidth > 850,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    installed == null
                        ? homeDescriptions[apps[index]]
                        : '${installed.game.platform}\n${installed.problem ?? 'Ready on this device. Pair your controllers, then play.'}',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 18,
                      height: 1.7,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 12)],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: installed == null ? 185 : 330,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: ConsoleButton(
                            focusNode: primary,
                            fill: ink,
                            onPressed: installing ? null : open,
                            child: Center(
                              child: Text(
                                installed == null
                                    ? 'Open'
                                    : installing
                                    ? 'Installing…'
                                    : installed.removing
                                    ? 'Finish deleting'
                                    : gamePlatform(
                                            installed.game,
                                            model.platforms,
                                          ) !=
                                          null
                                    ? 'Play'
                                    : 'View game',
                                style: const TextStyle(
                                  color: Color(0xff101923),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
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
                  const SizedBox(height: 44),
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_done_outlined,
                        size: 16,
                        color: accent,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Connected to ${Uri.parse(model.server!.address).host}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
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

class HomeGameTitle extends StatelessWidget {
  const HomeGameTitle({
    super.key,
    required this.title,
    this.logo,
    required this.wide,
  });
  final String title;
  final String? logo;
  final bool wide;
  @override
  Widget build(BuildContext context) {
    final fallback = Text(
      title,
      key: const ValueKey('home-game-title'),
      style: TextStyle(
        fontSize: wide ? 64 : 42,
        fontWeight: FontWeight.w300,
        height: 1.1,
        letterSpacing: -2,
        shadows: const [
          Shadow(color: Colors.black87, blurRadius: 18, offset: Offset(0, 2)),
        ],
      ),
    );
    return logo == null
        ? fallback
        : Image.file(
            File(logo!),
            key: const ValueKey('home-game-logo'),
            semanticLabel: title,
            width: wide ? 520 : 310,
            height: wide ? 154 : 112,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            cacheWidth: 1040,
            errorBuilder: (_, _, _) => fallback,
          );
  }
}
