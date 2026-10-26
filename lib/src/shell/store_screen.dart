import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../romm/models.dart';
import '../game_launch.dart';
import 'artwork.dart';
import 'controls.dart';
import 'navigation.dart';
import 'model.dart';
import 'download_status.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key, required this.model});
  final ShellModel model;
  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  ShellModel get model => widget.model;
  final scroll = ScrollController();
  final gameNodes = <int, FocusNode>{};
  final recentNodes = <int, FocusNode>{};
  final moreFocus = FocusNode(debugLabel: 'Load more games');
  SliverGridRegularTileLayout? gridLayout;
  double gridStart = 0;
  int moveSerial = 0;
  int? movingTo;
  int? moreOrigin;
  bool loadingMore = false;
  late String draft = model.search, applied = model.search;
  int searchActivation = 0;
  void consumeSearch() {
    if (model.controllerSearchPending) {
      model.controllerSearchPending = false;
      ++searchActivation;
    }
  }

  @override
  void initState() {
    super.initState();
    consumeSearch();
  }

  FocusNode gameNode(int id) =>
      gameNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'Store game $id'));

  @override
  void dispose() {
    ++moveSerial;
    scroll.dispose();
    moreFocus.dispose();
    for (final node in [...gameNodes.values, ...recentNodes.values]) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> focusGame(int index) async {
    final games = model.page?.games ?? [];
    if (index < 0 || index >= games.length || gridLayout == null) return;
    final id = games[index].id, node = gameNode(games[index].id);
    if (node.context != null) {
      ++moveSerial;
      movingTo = null;
      requestConsoleFocus(node);
      return;
    }
    final serial = ++moveSerial, source = FocusManager.instance.primaryFocus;
    movingTo = index;
    final geometry = gridLayout!.getGeometryForChildIndex(index);
    final start = gridStart + geometry.scrollOffset - 12;
    final end =
        start +
        geometry.mainAxisExtent +
        24 -
        scroll.position.viewportDimension;
    final offset = scroll.offset
        .clamp(math.min(start, end), math.max(start, end))
        .clamp(scroll.position.minScrollExtent, scroll.position.maxScrollExtent)
        .toDouble();
    final duration = motionDuration(context);
    if (duration == Duration.zero) {
      scroll.jumpTo(offset);
    } else {
      await scroll.animateTo(offset, duration: duration, curve: consoleCurve);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || serial != moveSerial) return;
      movingTo = null;
      if (FocusManager.instance.primaryFocus != source ||
          ModalRoute.of(context)?.isCurrent != true)
        return;
      if (model.page?.games.elementAtOrNull(index)?.id == id &&
          node.context != null)
        requestConsoleFocus(node);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool gameDirection(int index, TraversalDirection direction) {
    final games = model.page?.games ?? [];
    if (games.isEmpty || gridLayout == null) return true;
    index = movingTo ?? index;
    final columns = gridLayout!.crossAxisCount;
    int target;
    switch (direction) {
      case TraversalDirection.left:
        if (index % columns == 0) return true;
        target = index - 1;
      case TraversalDirection.right:
        if (index % columns == columns - 1 || index + 1 >= games.length)
          return true;
        target = index + 1;
      case TraversalDirection.up:
        if (index < columns) return false;
        target = index - columns;
      case TraversalDirection.down:
        if (index ~/ columns == (games.length - 1) ~/ columns) {
          moreOrigin = index;
          if (model.hasMore) requestConsoleFocus(moreFocus);
          return true;
        }
        target = math.min(index + columns, games.length - 1);
    }
    focusGame(target);
    return true;
  }

  Future<void> loadMore() async {
    if (loadingMore) return;
    setState(() => loadingMore = true);
    final count = model.page?.games.length ?? 0;
    await model.loadMore();
    if (!mounted) return;
    // Reveal the newly appended games, rather than leaving focus on a footer
    // that has just moved several rows away (or disappeared on the final page).
    final source = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted &&
          source == moreFocus &&
          (model.page?.games.length ?? 0) > count &&
          (FocusManager.instance.primaryFocus == source ||
              FocusManager.instance.primaryFocus is FocusScopeNode))
        await focusGame(count);
      if (mounted) setState(() => loadingMore = false);
    });
  }

  @override
  void didUpdateWidget(StoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    consumeSearch();
    if (model.search != applied) {
      draft = applied = model.search;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final narrow = size.maxWidth < 850, padding = narrow ? 24.0 : 56.0;
      final browsing = model.search.isNotEmpty || model.platformId != null;
      final games = model.page?.games ?? [];
      final featured = model.recent.firstOrNull ?? games.firstOrNull;
      final noCards = games.isEmpty && (browsing || featured == null);
      return CustomScrollView(
        key: const PageStorageKey('store-scroll'),
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padding, 12, padding, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Game Store',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w400,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 19),
                  SizedBox(
                    width: narrow ? size.maxWidth - padding * 2 : 420,
                    child: ConsoleFocusRegion(
                      leading: true,
                      child: ConsoleField(
                        label: 'Search games',
                        value: draft,
                        hint: 'Search your collection',
                        autofocus: true,
                        controllerRequest: searchActivation,
                        onChanged: (value) => draft = value,
                        onSubmitted: (value) => model.browse(term: value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConsoleFocusRegion(
                    trailing:
                        noCards &&
                        model.discoveryError == null &&
                        model.storeError == null &&
                        !model.hasMore,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ConsoleButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          onPressed: () => model.browse(term: draft),
                          child: const ActionLabel(
                            'Search',
                            icon: Icons.search,
                          ),
                        ),
                        ConsoleButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          fill: !browsing ? const Color(0xff315b54) : surface,
                          onPressed: () =>
                              model.browse(term: '', clearPlatform: true),
                          child: const Text('Discover'),
                        ),
                        ConsoleButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          onPressed: () => platformPicker(context, model),
                          child: ActionLabel(
                            model.platforms
                                    .where((p) => p.id == model.platformId)
                                    .firstOrNull
                                    ?.name ??
                                'All platforms',
                            icon: Icons.filter_list,
                          ),
                        ),
                        if (browsing)
                          ConsoleButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            onPressed: () =>
                                model.browse(term: '', clearPlatform: true),
                            child: const ActionLabel(
                              'Clear filters',
                              icon: Icons.close,
                            ),
                          ),
                        ConsoleButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          onPressed: model.storeBusy
                              ? null
                              : () => model.loadStore(),
                          label: 'Refresh collection',
                          child: const Icon(Icons.refresh, size: 18),
                        ),
                      ],
                    ),
                  ),
                  if (model.discoveryError != null)
                    ConsoleFocusRegion(
                      trailing:
                          noCards && model.storeError == null && !model.hasMore,
                      child: ProblemNotice(
                        model.discoveryError!,
                        retry: () => model.loadStore(),
                      ),
                    ),
                  if (!browsing && featured != null) ...[
                    const SizedBox(height: 28),
                    ConsoleFocusRegion(
                      child: SizedBox(
                        height: narrow ? 300 : 340,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              GameArtwork(
                                model: model,
                                game: featured,
                                backdrop: true,
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xff111e29),
                                      Color(0xee14232c),
                                      Color(0x2514232c),
                                    ],
                                    stops: [0, .42, 1],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.all(narrow ? 24 : 36),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Eyebrow('From your RomM'),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: narrow ? 350 : 520,
                                      child: Text(
                                        featured.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: narrow ? 30 : 40,
                                          fontWeight: FontWeight.w500,
                                          height: 1.15,
                                          letterSpacing: -.8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 13),
                                    Text(
                                      '${featured.platform}${featured.year == null ? '' : ' · ${featured.year}'}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    ConsoleButton(
                                      fill: ink,
                                      onPressed: () =>
                                          gameDetails(context, model, featured),
                                      child: const Text(
                                        'Explore game',
                                        style: TextStyle(
                                          color: Color(0xff15232a),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (!browsing && model.recent.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    const Text(
                      'Recently added',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 238,
                      child: ConsoleScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            for (var i = 0; i < model.recent.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 14),
                                child: SizedBox(
                                  width: 151,
                                  height: 214,
                                  child: ConsoleDirections(
                                    onDirection: (direction) {
                                      if (direction !=
                                              TraversalDirection.left &&
                                          direction != TraversalDirection.right)
                                        return false;
                                      final next =
                                          i +
                                          (direction == TraversalDirection.right
                                              ? 1
                                              : -1);
                                      if (next >= 0 &&
                                          next < model.recent.length)
                                        requestConsoleFocus(
                                          recentNodes[model.recent[next].id]!,
                                        );
                                      return true;
                                    },
                                    child: GameCard(
                                      focusNode: recentNodes.putIfAbsent(
                                        model.recent[i].id,
                                        () => FocusNode(
                                          debugLabel: 'Recent game $i',
                                        ),
                                      ),
                                      game: model.recent[i],
                                      model: model,
                                      onPressed: () => gameDetails(
                                        context,
                                        model,
                                        model.recent[i],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.search.isNotEmpty
                              ? 'Results for “${model.search}”'
                              : model.platforms
                                        .where((p) => p.id == model.platformId)
                                        .firstOrNull
                                        ?.name ??
                                    'Explore your collection',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (model.page?.total != null)
                        Text(
                          '${model.page!.total} ${model.page!.total == 1 ? 'game' : 'games'}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                    ],
                  ),
                  if (model.storeError != null)
                    ConsoleFocusRegion(
                      trailing: games.isEmpty && !model.hasMore,
                      child: ProblemNotice(
                        model.storeError!,
                        retry: () => model.page == null
                            ? model.browse()
                            : model.loadMore(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (model.storeBusy || model.page == null && model.storeError == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(42),
                child: Column(
                  children: [
                    SizedBox(
                      height: 26,
                      width: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Loading your collection…',
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
            )
          else if (games.isEmpty && model.storeError == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 30, padding, 70),
                child: Column(
                  children: [
                    const Icon(
                      Icons.videogame_asset_off_outlined,
                      color: muted,
                      size: 45,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      browsing
                          ? 'No games match those filters.'
                          : 'Your RomM collection has no games yet.',
                      style: const TextStyle(fontSize: 19),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      browsing
                          ? 'Try another platform or a shorter search.'
                          : 'Add games to RomM, then refresh your collection.',
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  const delegate = SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 205,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 16,
                    childAspectRatio: .64,
                  );
                  gridLayout = delegate.getLayout(
                    constraints,
                  ) as SliverGridRegularTileLayout;
                  gridStart = constraints.precedingScrollExtent;
                  return SliverGrid(
                    gridDelegate: delegate,
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => ConsoleFocusRegion(
                        key: ValueKey(games[i].id),
                        trailing:
                            !model.hasMore &&
                            !loadingMore &&
                            i ~/ gridLayout!.crossAxisCount ==
                                (games.length - 1) ~/
                                    gridLayout!.crossAxisCount,
                        child: ConsoleDirections(
                          onDirection: (direction) =>
                              gameDirection(i, direction),
                          child: GameCard(
                            focusNode: gameNode(games[i].id),
                            game: games[i],
                            model: model,
                            onPressed: () =>
                                gameDetails(context, model, games[i]),
                          ),
                        ),
                      ),
                      childCount: games.length,
                    ),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: model.hasMore || loadingMore
                    ? ConsoleFocusRegion(
                        trailing: true,
                        child: ConsoleDirections(
                          onDirection: (direction) {
                            if (direction == TraversalDirection.up)
                              focusGame(moreOrigin ?? games.length - 1);
                            return true;
                          },
                          child: ConsoleButton(
                            focusNode: moreFocus,
                            onPressed: loadMore,
                            child: Text(
                              model.moreBusy
                                  ? 'Loading more…'
                                  : 'Load more games',
                            ),
                          ),
                        ),
                      )
                    : games.isEmpty
                    ? const SizedBox(height: 8)
                    : const Text(
                        'You’re all caught up',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

Future<void> searchStore(BuildContext context, ShellModel model) async {
  model.controllerSearchPending = true;
  model.navigate(ShellScreen.store);
  // Store autofocus lands on the real search field. Controller activation
  // edits that field with the docked keyboard; keyboard Enter stays inline.
}

Future<void> platformPicker(BuildContext context, ShellModel model) =>
    showConsoleDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xff111d2a),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Choose a platform', style: TextStyle(fontSize: 25)),
                const SizedBox(height: 20),
                Expanded(
                  child: ConsoleScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConsoleButton(
                          autofocus: model.platformId == null,
                          onPressed: () {
                            Navigator.pop(context);
                            model.browse(clearPlatform: true);
                          },
                          child: const ActionLabel(
                            'All platforms',
                            icon: Icons.apps,
                          ),
                        ),
                        for (final platform in model.platforms)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ConsoleButton(
                              key: ValueKey('platform-choice-${platform.id}'),
                              autofocus: model.platformId == platform.id,
                              onPressed: () {
                                Navigator.pop(context);
                                model.browse(platform: platform.id);
                              },
                              child: Row(
                                children: [
                                  Expanded(child: Text(platform.name)),
                                  Text(
                                    '${platform.count}',
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

Future<void> gameDetails(
  BuildContext context,
  ShellModel model,
  RommGame game,
) {
  final future = model.detail(game);
  return showConsoleDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: model,
      builder: (context, _) => Dialog(
        backgroundColor: const Color(0xff111d2a),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950, maxHeight: 680),
          child: ConsoleScrollView(
            child: FutureBuilder<RommGame>(
              future: future,
              initialData: game,
              builder: (context, snapshot) {
                final current = snapshot.data ?? game,
                    wide = MediaQuery.sizeOf(context).width > 760;
                final installed = model.installation(current.id);
                final hasPrimaryAction =
                    model.queuedGame(current.id)?.state ==
                        DownloadState.active ||
                    (installed == null && !model.downloading) ||
                    (installed != null &&
                        installed.problem == null &&
                        gamePlatform(installed.game, model.platforms) != null);
                final description = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Eyebrow(current.platform),
                    const SizedBox(height: 15),
                    Text(
                      current.name,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        if (current.year != null)
                          Text(
                            '${current.year}',
                            style: const TextStyle(color: muted),
                          ),
                        if (current.rating != null)
                          Text(
                            '★ ${current.rating!.toStringAsFixed(0)}',
                            style: const TextStyle(color: accent),
                          ),
                        if (current.bytes > 0)
                          Text(
                            current.bytes >= 1024 * 1024 * 1024
                                ? '${(current.bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
                                : '${(current.bytes / (1024 * 1024)).toStringAsFixed(0)} MB',
                            style: const TextStyle(color: muted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _GameSummary(
                      current.summary.isEmpty
                          ? 'No description is available for this game.'
                          : current.summary,
                    ),
                    if (current.genres.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        current.genres.join(' · '),
                        style: const TextStyle(color: accent, fontSize: 12),
                      ),
                    ],
                    if (snapshot.hasError)
                      ProblemNotice(
                        'Game details could not be refreshed. ${snapshot.error}',
                      ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.only(top: 14),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    const SizedBox(height: 27),
                    DownloadStatus(model: model, game: current),
                    const SizedBox(height: 24),
                    ConsoleButton(
                      autofocus:
                          !hasPrimaryAction &&
                          ModalRoute.of(context)?.isCurrent == true,
                      fill: const Color(0xff315b54),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back'),
                    ),
                  ],
                );
                final cover = SizedBox(
                  width: wide ? 255 : 170,
                  height: wide ? 355 : 230,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GameArtwork(model: model, game: current),
                  ),
                );
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            cover,
                            const SizedBox(width: 34),
                            Expanded(child: description),
                          ],
                        )
                      : Column(
                          children: [
                            cover,
                            const SizedBox(height: 24),
                            description,
                          ],
                        ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// Long descriptions have a reachable reading region. Arrows/D-pad scroll the
/// text, then continue to the surrounding actions at its top and bottom edges.
class _GameSummary extends StatefulWidget {
  const _GameSummary(this.text);
  final String text;
  @override
  State<_GameSummary> createState() => _GameSummaryState();
}

class _GameSummaryState extends State<_GameSummary> {
  final scroll = ScrollController();
  final focus = FocusNode(debugLabel: 'Game description');
  bool focused = false;
  double? destination;

  @override
  void dispose() {
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  bool direction(TraversalDirection direction) {
    if (direction != TraversalDirection.up &&
        direction != TraversalDirection.down)
      return true;
    if (!scroll.hasClients) return false;
    final position = scroll.position;
    final previous = destination ?? position.pixels;
    final next =
        (previous +
                (direction == TraversalDirection.down ? 1 : -1) *
                    position.viewportDimension *
                    .7)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    if ((next - previous).abs() < .5) return false;
    destination = next;
    final duration = motionDuration(context);
    if (duration == Duration.zero) {
      scroll.jumpTo(next);
      destination = null;
    } else {
      scroll.animateTo(next, duration: duration, curve: consoleCurve).then((_) {
        if (destination == next) destination = null;
      });
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => ConsoleDirections(
    onDirection: direction,
    child: Focus(
      focusNode: focus,
      onFocusChange: (value) {
        setState(() => focused = value);
        if (value) revealConsoleFocus(focus);
      },
      child: Semantics(
        label: 'Game description',
        focused: focused,
        child: AnimatedContainer(
          duration: motionDuration(context),
          curve: consoleCurve,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: focused ? ink : Colors.white10, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: Scrollbar(
              controller: scroll,
              child: ConsoleScrollView(
                key: const ValueKey('game-description-scroll'),
                controller: scroll,
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  widget.text,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 14,
                    height: 1.8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
