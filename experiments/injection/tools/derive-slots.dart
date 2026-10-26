import 'dart:io';

// Offline metadata derivation from the reviewed SDL DynAPI ABI lists.
// Does not compile or ship SDL. Refresh only after reviewing upstream changes.
Future<void> main() async {
  final base = '${Directory.current.path}/experiments/injection';
  final wanted = {
    'SDL_Init',
    'SDL_GetTicks',
    'SDL_GetTicksNS',
    'SDL_GamepadHasSensor',
    'SDL_GamepadSensorEnabled',
    'SDL_SetGamepadSensorEnabled',
    'SDL_GetGamepadSensorData',
    'SDL_GetGamepadSensorDataRate',
    'SDL_GameControllerHasSensor',
    'SDL_GameControllerIsSensorEnabled',
    'SDL_GameControllerSetSensorEnabled',
    'SDL_GameControllerGetSensorData',
    'SDL_GameControllerGetSensorDataWithTimestamp',
    'SDL_GameControllerGetSensorDataRate',
    'SDL_DetachVirtualJoystick',
    'SDL_JoystickDetachVirtual',
    'SDL_CloseJoystick',
    'SDL_JoystickClose',
    'SDL_GameControllerName',
    'SDL_GameControllerGetAttached',
    'SDL_GameControllerClose',
    'SDL_IsGameController',
    'SDL_JoystickGetDeviceInstanceID',
    'SDL_JoystickGetDeviceGUID',
    'SDL_JoystickNameForIndex',
    'SDL_GameControllerNameForIndex',
    'SDL_GetGamepads',
    'SDL_IsGamepad',
    'SDL_GetGamepadPlayerIndex',
    'SDL_GetGamepadName',
    'SDL_GetGamepadType',
    'SDL_GameControllerGetType',
    'SDL_GamepadConnected',
    'SDL_CloseGamepad',
    'SDL_free',
    'SDL_calloc',
    'SDL_GetJoystickHat',
    'SDL_JoystickGetHat',
    'SDL_WasInit',
    'SDL_GetVersion',
    'SDL_GetGamepadButton',
    'SDL_GetJoystickButton',
    'SDL_LockJoysticks',
    'SDL_UnlockJoysticks',
    'SDL_GetGamepadAxis',
    'SDL_GetJoystickAxis',
    'SDL_GetGamepadJoystick',
    'SDL_GetJoystickID',
    'SDL_GameControllerGetButton',
    'SDL_JoystickGetButton',
    'SDL_GameControllerGetAxis',
    'SDL_JoystickGetAxis',
    'SDL_GameControllerGetJoystick',
    'SDL_JoystickInstanceID',
    'SDL_PollEvent',
    'SDL_PeepEvents',
    'SDL_WaitEvent',
    'SDL_WaitEventTimeout',
    'SDL_AddEventWatch',
    'SDL_DelEventWatch',
    'SDL_RemoveEventWatch',
    'SDL_OpenGamepad',
    'SDL_OpenJoystick',
    'SDL_GameControllerOpen',
    'SDL_JoystickOpen',
    'SDL_AttachVirtualJoystick',
    'SDL_JoystickAttachVirtual',
    'SDL_SetJoystickVirtualButton',
    'SDL_SetJoystickVirtualAxis',
    'SDL_JoystickSetVirtualButton',
    'SDL_JoystickSetVirtualAxis',
    'SDL_UpdateJoysticks',
    'SDL_JoystickUpdate',
    'SDL_PushEvent',
    'SDL_GetJoysticks',
    'SDL_NumJoysticks',
    'SDL_GetJoystickName',
    'SDL_JoystickName',
    'SDL_GetJoystickGUID',
    'SDL_JoystickGetGUID',
    'SDL_GetJoystickGUIDString',
    'SDL_JoystickGetGUIDString',
  };
  final output = StringBuffer(
    '// Derived API slot metadata, macOS ABI. See SOURCES.md.\n',
  );
  for (final major in [2, 3]) {
    final source = File('$base/build/slots$major.c');
    await source.writeAsString(
      '#define SDL_DYNAPI_PROC(ret,func,args,args2,retstmt) BROOMM_SLOT(func)\n#include "../reference/SDL${major}_dynapi_procs.h"\n',
    );
    final result = await Process.run('/usr/bin/xcrun', [
      'clang',
      '-E',
      '-P',
      '-D__MACOSX__=1',
      source.path,
    ]);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
    final names = RegExp(r'BROOMM_SLOT\((\w+)\)')
        .allMatches(result.stdout as String)
        .map((m) => m[1]!)
        .toList();
    output.writeln('#if BROOMM_SDL_MAJOR == $major');
    output.writeln('static const struct ApiSlot known_slots[] = {');
    for (var i = 0; i < names.length; i++) {
      if (wanted.contains(names[i])) output.writeln('    {"${names[i]}",$i},');
    }
    output.writeln('};\n#endif');
    stdout.writeln(
      'SDL$major: ${names.length} slots, selected ${names.where(wanted.contains).length}',
    );
  }
  await File('$base/src/abi_slots.h').writeAsString(output.toString());
}
