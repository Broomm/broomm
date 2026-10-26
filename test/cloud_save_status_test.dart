import 'dart:io';

import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const server = '0123456789abcdef0123456789abcdef',
      profile = '1123456789abcdef0123456789abcdef';
  late Directory data;
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-cloud-status-');
  });
  tearDown(() async {
    await data.delete(recursive: true);
  });
  Future<void> state(Map<String, dynamic> value) async => progressWrite(
    await progressFile(
      data,
      'cloud-saves/$server/$profile/1/state.json',
      createParents: true,
    ),
    value,
  );
  Future<CloudSaveStatus> read() =>
      readCloudSaveStatus(data, server, profile, 1);
  test('only an acknowledged current-profile result is synced; an offline edit or retained conflict changes its badge', () async {
    expect(await read(), CloudSaveStatus.waiting);
    final synced = {
      'pending': false,
      'baseline': 'a' * 64,
      'synced': DateTime.now().toUtc().toIso8601String(),
    };
    await state(synced);
    expect(await read(), CloudSaveStatus.synced);
    expect(
      await readCloudSaveStatus(
        data,
        server,
        '2123456789abcdef0123456789abcdef',
        1,
      ),
      CloudSaveStatus.waiting,
    );
    await state({...synced, 'pending': true});
    expect(await read(), CloudSaveStatus.waiting);
    await state({
      ...synced,
      'conflict': {'reason': 'other device'},
    });
    expect(await read(), CloudSaveStatus.attention);
    await state({...synced, 'unclean': true});
    expect(await read(), CloudSaveStatus.attention);
    await state({...synced, 'active': true});
    expect(await read(), CloudSaveStatus.waiting);
  });
  test('verified absence can be synced, while a corrupt record, interrupted restore or linked storage needs attention without repairing it', () async {
    await state({'pending': false});
    expect(await read(), CloudSaveStatus.waiting);
    await state({
      'pending': false,
      'emptySynced': true,
      'synced': '2026-10-22T12:00:00Z',
    });
    expect(await read(), CloudSaveStatus.synced);
    final file = File('${data.path}/cloud-saves/$server/$profile/1/state.json');
    final before = await file.readAsString();
    final restore = File('${file.parent.path}/restore.json');
    await restore.writeAsString('{}');
    expect(await read(), CloudSaveStatus.attention);
    expect(await file.readAsString(), before);
    await restore.delete();
    await file.writeAsString('{');
    expect(await read(), CloudSaveStatus.attention);
    expect(await file.readAsString(), '{');
    await file.delete();
    await Link(file.path).create('${data.path}/foreign-save');
    expect(await read(), CloudSaveStatus.attention);
    expect(
      File(await Link(file.path).target()).uri,
      File('${data.path}/foreign-save').uri,
    );
  });
}
