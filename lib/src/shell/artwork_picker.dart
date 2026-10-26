import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../romm/models.dart';
import '../steamgrid.dart';
import 'controls.dart';
import 'navigation.dart';
import 'library.dart';
import 'model.dart';
import 'cloud_saves_dialog.dart';

Future<bool?> steamGridSettings(BuildContext context, ShellModel model) =>
    showConsoleDialog<bool>(
      context: context,
      builder: (_) => _KeyDialog(model: model),
    );

class _KeyDialog extends StatefulWidget {
  const _KeyDialog({required this.model});
  final ShellModel model;
  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  String value = '';
  String? error;
  bool busy = false;
  Future<void> save({bool remove = false}) async {
    final m = widget.model, s = m.server, p = m.profile;
    if (s == null || p == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (remove) {
        await m.steamGridCredentials.delete(p);
      } else {
        await m.steamGridCredentials.write(s, p, value);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'The SteamGridDB key could not be saved or removed. Check the key and unlock your system secure store, then retry.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConsoleScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('SteamGridDB artwork', style: TextStyle(fontSize: 28)),
              const SizedBox(height: 16),
              const Text(
                'Use your SteamGridDB API key to choose square icons, heroes and game logos. The key is stored securely for this RomM profile, separately from its sign-in.',
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 10),
              const SelectableText(
                'Create a key at https://www.steamgriddb.com/profile/preferences/api',
                style: TextStyle(color: accent, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ConsoleField(
                label: 'SteamGridDB API key',
                value: value,
                secret: true,
                autofocus: true,
                onChanged: (v) => value = v,
                onSubmitted: (_) => save(),
              ),
              if (error != null) ProblemNotice(error!),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ConsoleButton(
                    onPressed: busy ? null : save,
                    child: Text(busy ? 'Saving…' : 'Save key'),
                  ),
                  ConsoleButton(
                    onPressed: busy ? null : () => save(remove: true),
                    child: const Text('Remove saved key'),
                  ),
                  ConsoleButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ArtworkSession {
  _ArtworkSession(this.model) : revision = model.contextRevision;
  final ShellModel model;
  final int revision;
  bool closed = false;
  SteamGridClient? client;
  Future<SteamGridClient> connection() async {
    if (closed || revision != model.contextRevision)
      throw const RommFailure('Artwork selection was closed.');
    if (client != null) return client!;
    final value = await model.artworkClient();
    if (closed || revision != model.contextRevision) {
      value.close();
      throw const RommFailure('Artwork selection was closed.');
    }
    return client = value;
  }

  void reset() {
    client?.close();
    client = null;
  }

  void close() {
    closed = true;
    reset();
  }
}

class _Pick {
  const _Pick(this.image);
  final ArtworkDownload? image;
}

Future<void> selectGameArtwork(
  BuildContext context,
  ShellModel model,
  RommGame original, {
  bool refresh = false,
}) async {
  final revision = model.contextRevision;
  final session = _ArtworkSession(model);
  bool current() =>
      context.mounted && !model.disposed && revision == model.contextRevision;
  try {
    final game = refresh ? await model.detail(original) : original;
    if (!current()) return;
    if (game.sgdbId == null) {
      await showConsoleDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('No mapped artwork'),
          content: const Text(
            'This game has no SteamGridDB entry mapped in RomM. The current poster icon and Broomm background will be used.',
          ),
          actions: [
            ConsoleButton(
              autofocus: true,
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    final icon = await showConsoleDialog<_Pick>(
      context: context,
      builder: (_) =>
          _ArtworkPicker(session: session, game: game, kind: ArtworkKind.icon),
    );
    if (!current() || icon == null) return;
    final hero = await showConsoleDialog<_Pick>(
      context: context,
      builder: (_) =>
          _ArtworkPicker(session: session, game: game, kind: ArtworkKind.hero),
    );
    if (!current()) return;
    final logo = hero == null
        ? null
        : await showConsoleDialog<_Pick>(
            context: context,
            builder: (_) => _ArtworkPicker(
              session: session,
              game: game,
              kind: ArtworkKind.logo,
            ),
          );
    if (!current()) return;
    if (icon.image != null || hero?.image != null || logo?.image != null) {
      await model.saveGameArtwork(
        game.id,
        icon: icon.image,
        hero: hero?.image,
        logo: logo?.image,
      );
      if (current()) model.showNotice('Home artwork saved.');
    }
  } catch (e) {
    if (current())
      await showConsoleDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Artwork was not changed'),
          content: Text(
            e is RommFailure ? e.message : 'The artwork could not be saved. Existing game files and progress have been kept.',
          ),
          actions: [
            ConsoleButton(
              autofocus: true,
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );
  } finally {
    session.close();
  }
}

class _ArtworkPicker extends StatefulWidget {
  const _ArtworkPicker({
    required this.session,
    required this.game,
    required this.kind,
  });
  final _ArtworkSession session;
  final RommGame game;
  final ArtworkKind kind;
  @override
  State<_ArtworkPicker> createState() => _ArtworkPickerState();
}

class _ArtworkPickerState extends State<_ArtworkPicker> {
  final images = <GridArtwork>[];
  final thumbs = <Uri, Future<Uint8List>>{};
  String? error;
  bool loading = true, selecting = false, more = false;
  int page = 0;
  int attemptedPage = 0;
  Object requestOwner = Object();
  final firstChoice = FocusNode(debugLabel: 'First artwork on page');
  @override
  void dispose() {
    widget.session.client?.cancelRequests(requestOwner);
    firstChoice.dispose();
    super.dispose();
  }

  Future<Uint8List> thumbnail(Uri uri) async {
    final owner = requestOwner;
    final bytes = await (await widget.session.connection()).image(
      uri,
      thumbnail: true,
      owner: owner,
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width > 8192 ||
          descriptor.height > 8192 ||
          descriptor.width * descriptor.height > 32 * 1024 * 1024 ||
          (widget.kind == ArtworkKind.icon &&
              descriptor.width != descriptor.height) ||
          (widget.kind == ArtworkKind.hero &&
              descriptor.width <= descriptor.height))
        throw const FormatException('Oversized artwork preview');
      return bytes;
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({int target = 0}) async {
    if (selecting) return;
    widget.session.client?.cancelRequests(requestOwner);
    final owner = requestOwner = Object();
    final previousPage = page;
    attemptedPage = target;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final client = await widget.session.connection();
      if (!mounted || !identical(owner, requestOwner)) return;
      final result = await client.page(
        widget.game.sgdbId!,
        widget.kind,
        page: target,
        owner: owner,
      );
      if (!mounted || !identical(owner, requestOwner)) return;
      setState(() {
        images.clear();
        thumbs.clear();
        page = target;
        final known = images.map((e) => e.id).toSet();
        images.addAll(result.images.where((e) => known.add(e.id)));
        more = result.hasMore;
      });
      if (target != previousPage)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) requestConsoleFocus(firstChoice);
        });
    } catch (e) {
      if (mounted && identical(owner, requestOwner))
        setState(
          () => error = e is RommFailure
              ? e.message
              : 'Artwork could not be loaded. Unlock secure storage and retry.',
        );
    } finally {
      if (mounted && identical(owner, requestOwner))
        setState(() => loading = false);
    }
  }

  Future<void> choose(GridArtwork art) async {
    setState(() {
      selecting = true;
      error = null;
    });
    try {
      final client = await widget.session.connection();
      if (!mounted) return;
      final bytes = await client.image(art.url, owner: requestOwner);
      final selected = ArtworkDownload(art, bytes);
      validateArtworkDownload(selected);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width != art.width || descriptor.height != art.height)
          throw const FormatException('Dimensions changed');
        codec = await descriptor.instantiateCodec(
          targetWidth: widget.kind == ArtworkKind.icon ? 256 : 960,
        );
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
      if (mounted) Navigator.pop(context, _Pick(selected));
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is RommFailure
              ? e.message
              : 'This image could not be verified. Choose another artwork.',
        );
    } finally {
      if (mounted) setState(() => selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.kind == ArtworkKind.icon;
    final logo = widget.kind == ArtworkKind.logo;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1050),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                icon
                    ? 'Choose a square icon'
                    : logo
                    ? 'Choose a logo'
                    : 'Choose a background',
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(height: 8),
              Text(
                '${icon
                    ? '1 of 3 · Square PNG grids'
                    : logo
                    ? '3 of 3 · SteamGridDB logos'
                    : '2 of 3 · SteamGridDB heroes'} · ${widget.game.name}',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: ConsoleScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (error != null) ProblemNotice(error!),
                      if (images.isEmpty && !loading && error == null)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            icon
                                ? 'No square PNG icons are available for this entry.'
                                : logo
                                ? 'No logos are available for this entry. The game title stays visible.'
                                : 'No heroes are available for this entry.',
                            style: const TextStyle(color: muted),
                          ),
                        ),
                      LayoutBuilder(
                        builder: (context, size) {
                          final count = (size.maxWidth / (icon ? 190 : 300))
                              .floor()
                              .clamp(1, 4);
                          final width =
                              (size.maxWidth - (count - 1) * 14) / count;
                          return Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              for (final image in images)
                                SizedBox(
                                  width: width,
                                  child: ConsoleButton(
                                    key: ValueKey(
                                      'artwork-${image.kind.name}-${image.id}',
                                    ),
                                    autofocus: images.first == image,
                                    focusNode: images.first == image
                                        ? firstChoice
                                        : null,
                                    onPressed: selecting
                                        ? null
                                        : () => choose(image),
                                    padding: const EdgeInsets.all(7),
                                    label: 'Artwork by ${image.author}',
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        AspectRatio(
                                          aspectRatio: icon
                                              ? 1
                                              : logo
                                              ? 2
                                              : 3.1,
                                          child: FutureBuilder<Uint8List>(
                                            future: thumbs.putIfAbsent(
                                              image.thumb,
                                              () => thumbnail(image.thumb),
                                            ),
                                            builder: (c, s) => s.data == null
                                                ? const ColoredBox(
                                                    color: surface,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.image_outlined,
                                                        color: muted,
                                                      ),
                                                    ),
                                                  )
                                                : Image.memory(
                                                    s.data!,
                                                    fit: BoxFit.contain,
                                                    cacheWidth: icon
                                                        ? 240
                                                        : 480,
                                                    errorBuilder: (_, _, _) =>
                                                        const Icon(
                                                          Icons
                                                              .broken_image_outlined,
                                                        ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${image.width} × ${image.height} · ${image.author}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                          );
                        },
                      ),
                      if (loading || selecting)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Column(
                            children: [
                              const LinearProgressIndicator(),
                              const SizedBox(height: 8),
                              Text(
                                selecting
                                    ? 'Downloading and verifying artwork…'
                                    : 'Loading artwork…',
                                style: const TextStyle(color: muted),
                              ),
                            ],
                          ),
                        ),
                      if (page > 0 && !loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: ConsoleButton(
                            onPressed: selecting
                                ? null
                                : () => load(target: page - 1),
                            child: const Text('Previous page'),
                          ),
                        ),
                      if (more && !loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: ConsoleButton(
                            onPressed: selecting
                                ? null
                                : () => load(target: page + 1),
                            child: const Text('Next page'),
                          ),
                        ),
                      if (error != null)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ConsoleButton(
                              onPressed: loading || selecting
                                  ? null
                                  : () => load(target: attemptedPage),
                              child: const Text('Retry'),
                            ),
                            ConsoleButton(
                              onPressed: selecting
                                  ? null
                                  : () async {
                                      if (await steamGridSettings(
                                            context,
                                            widget.session.model,
                                          ) ==
                                          true) {
                                        widget.session.reset();
                                        thumbs.clear();
                                        await load();
                                      }
                                    },
                              child: const Text('Configure API key'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ConsoleButton(
                    autofocus: true,
                    onPressed: selecting
                        ? null
                        : () => Navigator.pop(context, const _Pick(null)),
                    child: Text(
                      icon
                          ? 'Keep current icon'
                          : logo
                          ? 'Keep current logo'
                          : 'Keep current background',
                    ),
                  ),
                  ConsoleButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> homeGameOptions(
  BuildContext context,
  ShellModel model,
  RommGame game,
) async {
  final action = await showConsoleDialog<String>(
    context: context,
    builder: (c) => ListenableBuilder(
      listenable: model,
      builder: (context, _) => AlertDialog(
        scrollable: true,
        title: Text(game.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (model.downloading)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Finish the current download before changing artwork or deleting this game.',
                ),
              ),
            ConsoleButton(
              autofocus: true,
              onPressed:
                  model.downloading ||
                      model.busy ||
                      model.gameActive ||
                      model.installation(game.id)?.removing == true
                  ? null
                  : () => Navigator.pop(c, 'artwork'),
              child: const ActionLabel(
                'Select Artwork',
                icon: Icons.collections_outlined,
              ),
            ),
            const SizedBox(height: 12),
            if (model.supportsAddons(game)) ...[
              ConsoleButton(
                onPressed:
                    model.downloading ||
                        model.busy ||
                        model.gameActive ||
                        model.installation(game.id)?.removing == true
                    ? null
                    : () => Navigator.pop(c, 'addons'),
                child: const ActionLabel(
                  'Download Updates and DLC',
                  icon: Icons.system_update_alt,
                ),
              ),
              const SizedBox(height: 12),
            ],
            ConsoleButton(
              onPressed: model.downloading || model.busy || model.gameActive
                  ? null
                  : () => Navigator.pop(c, 'delete'),
              child: const ActionLabel('Delete', icon: Icons.delete_outline),
            ),
            for (final entry in const {
              'save-use': 'Use existing save file',
              'save-backup': 'Backup savefile',
              'save-sync': 'Cloud saves',
            }.entries) ...[
              const SizedBox(height: 12),
              ConsoleButton(
                onPressed: model.downloading || model.busy || model.gameActive
                    ? null
                    : () => Navigator.pop(c, entry.key),
                child: ActionLabel(entry.value, icon: Icons.cloud_outlined),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  if (action != null && action.startsWith('save-')) {
    await manageCloudSaves(context, model, game, action);
    return;
  }
  if (action == 'artwork') {
    await selectGameArtwork(context, model, game, refresh: true);
    return;
  }
  if (action == 'addons') {
    await model.downloadUpdatesAndDlc(game.id);
    return;
  }
  if (action != 'delete') return;
  final confirmed = await showConsoleDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete ${game.name}?'),
      content: const Text(
        'Remove this downloaded game, its updates/DLC and chosen artwork from this device for all Broomm profiles on this server? Add-ons still used by another installed version are kept. Saves and save states are kept. Nothing is deleted from RomM.',
      ),
      actions: [
        ConsoleButton(
          autofocus: true,
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        ConsoleButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete game'),
        ),
      ],
    ),
  );
  if (confirmed == true) await model.deleteGame(game.id);
}
