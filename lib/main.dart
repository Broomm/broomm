import 'dart:io';

import 'package:flutter/material.dart';

import 'src/app_model.dart';
import 'src/shell/app.dart';
import 'src/shell/model.dart';
import 'src/shell/storage.dart';
import 'src/session_log.dart';
import 'controller_lab.dart';
export 'controller_lab.dart' show BroommPrototype;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final project = developmentProject();
  if (const bool.fromEnvironment('BROOMM_CONTROLLER_LAB')) {
    runApp(
      BroommPrototype(model: PrototypeModel(project ?? Directory.current.path)),
    );
    return;
  }
  try {
    final storage = ShellStorage(await ShellStorage.defaultDirectory());
    await storage.directory.create(recursive: true);
    late final ShellModel model;
    final log = SessionLog(
      '${storage.directory.path}/broomm.log',
      source: 'romm.dart',
      onProblem: (message) {
        model.reportProblem(message);
      },
    );
    model = ShellModel(storage, log: log, project: project);
    runApp(BroommApp(model: model, project: project));
    await model.start();
  } catch (_) {
    runApp(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: Center(
            child: Text(
              'Broomm could not open its application storage. Check file access and restart.',
            ),
          ),
        ),
      ),
    );
  }
}
