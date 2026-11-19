import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'model.dart';
import 'navigation.dart';

/// Top-aligned cover art over the existing atmosphere and bottom fade.
class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key, required this.model});
  final ShellModel model;

  @override
  Widget build(BuildContext context) {
    final path =
        model.screen == ShellScreen.home && model.preferences.showArtwork
        ? model.selectedHomeGame?.artwork?.hero
        : null;
    return IgnorePointer(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: motionDuration(context),
          child: path == null
              ? const SizedBox.expand(key: ValueKey('no-home-hero'))
              : RepaintBoundary(
                  key: ValueKey(path),
                  child: ClipRect(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0, .5, 1],
                      ).createShader(bounds),
                      child: _PanningHero(
                        path: path,
                        cacheWidth:
                            (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round()
                                .clamp(1, 3840),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _PanningHero extends StatefulWidget {
  const _PanningHero({required this.path, required this.cacheWidth});
  final String path;
  final int cacheWidth;
  @override
  State<_PanningHero> createState() => _PanningHeroState();
}

class _PanningHeroState extends State<_PanningHero>
    with WidgetsBindingObserver {
  final alignment = ValueNotifier<double>(-1);
  ImageProvider? provider;
  ImageStream? stream;
  ImageStreamListener? listener;
  double? aspect;
  Timer? timer;
  int elapsedMs = 0;
  bool visible = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    visible =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    resolveImage();
  }

  @override
  void didUpdateWidget(_PanningHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      aspect = null;
      stop(reset: true);
    }
    if (oldWidget.path != widget.path ||
        oldWidget.cacheWidth != widget.cacheWidth)
      resolveImage();
  }

  void resolveImage() {
    final next = ResizeImage.resizeIfNeeded(
      widget.cacheWidth,
      null,
      FileImage(File(widget.path)),
    );
    if (provider == next) return;
    if (listener != null) stream?.removeListener(listener!);
    provider = next;
    final resolved = next.resolve(createLocalImageConfiguration(context));
    stream = resolved;
    late final ImageStreamListener metadata;
    metadata = ImageStreamListener(
      (info, synchronous) {
        final ratio = info.image.width / info.image.height;
        info.dispose();
        // One frame supplies dimensions. Do not keep animated image decoding
        // alive independently of Image's own visibility/ticker handling.
        resolved.removeListener(metadata);
        if (!mounted || listener != metadata) return;
        listener = null;
        if (aspect != ratio) setState(() => aspect = ratio);
      },
      onError: (Object error, StackTrace? stack) {
        resolved.removeListener(metadata);
        if (!mounted || listener != metadata) return;
        listener = null;
        stop(reset: true);
        setState(() => aspect = null);
      },
    );
    listener = metadata;
    resolved.addListener(metadata);
  }

  void stop({bool reset = false}) {
    timer?.cancel();
    timer = null;
    if (reset) {
      elapsedMs = 0;
      alignment.value = -1;
    }
  }

  void start() {
    if (timer != null) return;
    var previous = 0;
    // Only this image subtree updates. Request frames on demand so finite
    // page transitions can settle while the ambient movement continues.
    timer = Timer.periodic(const Duration(milliseconds: 50), (tick) {
      elapsedMs = (elapsedMs + (tick.tick - previous) * 50) % 46000;
      previous = tick.tick;
      final phase = elapsedMs;
      alignment.value = phase < 3000
          ? -1
          : phase < 23000
          ? -1 + 2 * Curves.easeInOut.transform((phase - 3000) / 20000)
          : phase < 26000
          ? 1
          : 1 - 2 * Curves.easeInOut.transform((phase - 26000) / 20000);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final next =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (!next) stop();
    if (visible != next) setState(() => visible = next);
  }

  @override
  void dispose() {
    stop();
    if (listener != null) stream?.removeListener(listener!);
    alignment.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final ticking = TickerMode.valuesOf(context).enabled;
    return LayoutBuilder(
      builder: (context, bounds) {
        final overflow =
            aspect != null && aspect! * bounds.maxHeight - bounds.maxWidth > 1;
        if (overflow && !reduced && ticking && visible) {
          start();
        } else {
          stop(reset: reduced || !overflow);
        }
        return ValueListenableBuilder<double>(
          valueListenable: alignment,
          builder: (context, x, _) => Image(
            image: provider!,
            key: const ValueKey('home-hero-image'),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            alignment: Alignment(x, -1),
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        );
      },
    );
  }
}
