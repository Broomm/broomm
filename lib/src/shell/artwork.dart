import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';

import '../romm/models.dart';
import 'controls.dart';
import 'model.dart';
import 'navigation.dart';

/// The existing atmosphere stays behind this transparent, top-aligned image.
class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key, required this.model});
  final ShellModel model;
  @override
  Widget build(BuildContext context) {
    final index = model.homeIndex - model.homeAppCount;
    final path =
        model.screen == ShellScreen.home &&
            model.preferences.showArtwork &&
            index >= 0 &&
            index < model.installed.length
        ? model.installed[index].artwork?.hero
        : null;
    return IgnorePointer(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: motionDuration(context),
          child: path == null
              ? const SizedBox.expand(key: ValueKey('no-home-hero'))
              : ClipRect(
                  key: ValueKey(path),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0, .5, 1],
                    ).createShader(bounds),
                    child: Image.file(
                      File(path),
                      key: const ValueKey('home-hero-image'),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      cacheWidth:
                          (MediaQuery.sizeOf(context).width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round()
                              .clamp(1, 3840),
                      errorBuilder: (_, _, _) => const SizedBox.expand(),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class GameArtwork extends StatelessWidget {
  const GameArtwork({
    super.key,
    required this.model,
    required this.game,
    this.backdrop = false,
    this.compact = false,
  });
  final ShellModel model;
  final RommGame game;
  final bool backdrop;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final path = backdrop ? game.backdrop ?? game.cover : game.cover;
    final colors = [
      const Color(0xff334a58),
      const Color(0xff493b63),
      const Color(0xff235351),
      const Color(0xff674a3d),
    ];
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors[game.id % colors.length], const Color(0xff101923)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sports_esports_outlined,
                size: backdrop ? 80 : 38,
                color: Colors.white24,
              ),
              if (!compact) ...[
                const SizedBox(height: 12),
                Text(
                  game.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: backdrop ? 25 : 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (path == null || path.isEmpty || !model.preferences.showArtwork)
      return placeholder;
    return FutureBuilder<Uint8List?>(
      future: model.artwork(path),
      builder: (context, snapshot) {
        if (snapshot.data == null) return placeholder;
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          cacheWidth: backdrop ? 1440 : 420,
          errorBuilder: (_, _, _) => placeholder,
        );
      },
    );
  }
}

class GameCard extends StatefulWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.model,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
  });
  final RommGame game;
  final ShellModel model;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard>
    with AutomaticKeepAliveClientMixin {
  final ownedNode = FocusNode();
  FocusNode get node => widget.focusNode ?? ownedNode;
  // A rapid held direction can scroll beyond Flutter's cache before the next
  // card mounts. Retain the input owner until focus reaches its destination.
  @override
  bool get wantKeepAlive =>
      node.hasFocus || node.nearestScope?.focusedChild == node;
  @override
  void initState() {
    super.initState();
    node.addListener(updateKeepAlive);
    FocusManager.instance.addListener(updateKeepAlive);
  }

  @override
  void didUpdateWidget(GameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? ownedNode).removeListener(updateKeepAlive);
      node.addListener(updateKeepAlive);
      updateKeepAlive();
    }
  }

  @override
  void dispose() {
    node.removeListener(updateKeepAlive);
    FocusManager.instance.removeListener(updateKeepAlive);
    ownedNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final game = widget.game;
    return ConsoleButton(
      onPressed: widget.onPressed,
      autofocus: widget.autofocus,
      focusNode: node,
      label: '${game.name}, ${game.platform}',
      padding: EdgeInsets.zero,
      radius: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GameArtwork(model: widget.model, game: game),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${game.platform}${game.versions.length > 1 ? ' · ${game.versions.length} versions' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
