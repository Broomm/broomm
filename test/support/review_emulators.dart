import 'package:broomm/src/managed_emulators.dart';

/// Exercises the macOS recipe's presentation and validation on every test host.
/// These tests never install or start the referenced native executables.
class ReviewEmulators extends ManagedEmulators {
  ReviewEmulators(super.data, {super.project});
  @override
  String get host => 'macos-arm64';
}
