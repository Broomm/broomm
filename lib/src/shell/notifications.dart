import 'dart:async';

import 'package:flutter/material.dart';

import 'controls.dart';
import 'model.dart';
import 'navigation.dart';

/// Overlay feedback occupies no page space and never takes focus on arrival.
/// Ongoing work remains reachable; only completed-event cards expire.
class ShellNotifications extends StatefulWidget {
  const ShellNotifications({super.key, required this.model});
  final ShellModel model;
  @override
  State<ShellNotifications> createState() => _ShellNotificationsState();
}

class _ShellNotificationsState extends State<ShellNotifications> {
  Timer? timer;
  ShellNotice? visible;
  int? seen;
  @override
  void initState() {
    super.initState();
    widget.model.addListener(update);
    update();
  }

  @override
  void didUpdateWidget(ShellNotifications old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) {
      old.model.removeListener(update);
      widget.model.addListener(update);
      seen = null;
      update();
    }
  }

  void update() {
    final next = widget.model.notice;
    if (next?.id == seen) return;
    timer?.cancel();
    seen = next?.id;
    visible = next;
    if (next != null) {
      timer = Timer(Duration(seconds: next.problem ? 12 : 7), () {
        if (mounted) setState(() => visible = null);
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.model.removeListener(update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final message = visible;
    final shown = m.authenticated && !m.gameActive && message != null;
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: AnimatedSwitcher(
            duration: motionDuration(context),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(-.08, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: !shown
                ? const SizedBox.shrink()
                : ConstrainedBox(
                    key: ValueKey(message.id),
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Material(
                      key: const ValueKey('shell-notification'),
                      color: const Color(0xff1c2937),
                      elevation: 18,
                      shadowColor: Colors.black54,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              message.problem
                                  ? Icons.info_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: message.problem
                                  ? const Color(0xffefd3aa)
                                  : accent,
                              size: 28,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  message.message,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: ink,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
