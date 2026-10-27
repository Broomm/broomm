import 'package:flutter/services.dart';

class DesktopHost {
  static const channel = MethodChannel('app.broomm/prototype');
  Future<void> show({List<double>? frame, bool overlay = false}) async {
    try {
      await channel.invokeMethod<void>('show', {
        'frame': frame,
        'overlay': overlay,
      });
    } on MissingPluginException {
      /* Other hosts can preview Flutter UI. */
    }
  }

  Future<void> hide(int pid) async {
    try {
      await channel.invokeMethod<void>('hide', {'pid': pid});
    } on MissingPluginException {}
  }

  Future<void> close() async {
    try {
      await channel.invokeMethod<void>('close');
    } on MissingPluginException {}
  }

  Future<Map<String, dynamic>?> gameWriter(String root) async {
    try {
      return await channel.invokeMapMethod<String, dynamic>('gameWriter', {
        'root': root,
      });
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> controlGameWriter(String token, String action) =>
      channel.invokeMethod<void>('controlGameWriter', {
        'token': token,
        'action': action,
      });
}
