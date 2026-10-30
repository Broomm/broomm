import 'package:broomm/src/progress/files.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/android_document_paths.dart';

void main() {
  test('Windows drive paths produce the nested Android document path', () {
    final relative = androidDocumentRelativePath(
      Uri.directory(r'D:\fixture\citra-emu', windows: true),
      Uri.file(
        r'D:\fixture\citra-emu\sdmc\Nintendo 3DS\title\data\main',
        windows: true,
      ),
    );
    expect(relative, 'sdmc/Nintendo 3DS/title/data/main');
    progressRelative(relative);
  });

  test('Windows UNC paths retain decoded document names', () {
    final relative = androidDocumentRelativePath(
      Uri.directory(r'\\server\share\saves', windows: true),
      Uri.file(r'\\server\share\saves\Pokémon #1%\main.sav', windows: true),
    );
    expect(relative, 'Pokémon #1%/main.sav');
    progressRelative(relative);
    expect(
      () => androidDocumentRelativePath(
        Uri.directory(r'\\server\share\saves', windows: true),
        Uri.file(r'\\other\share\saves\main.sav', windows: true),
      ),
      throwsArgumentError,
    );
  });

  test(
    'POSIX names stay literal and invalid transport paths stay rejected',
    () {
      final root = Uri.directory('/fixture/saves', windows: false);
      expect(
        androidDocumentRelativePath(
          root,
          Uri.file('/fixture/saves/nested/main.sav', windows: false),
        ),
        'nested/main.sav',
      );
      final invalid = androidDocumentRelativePath(
        root,
        Uri.file(r'/fixture/saves/nested\main.sav', windows: false),
      );
      expect(() => progressRelative(invalid), throwsFormatException);
      expect(
        () => androidDocumentRelativePath(
          root,
          Uri.file('/fixture/saves-other/main.sav', windows: false),
        ),
        throwsArgumentError,
      );
    },
  );
}
