import 'package:broomm/src/addons/package_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'publication replaces mixed Windows staging paths in both native indexes',
    () {
      final replacements = {
        Uri.parse('file:///C:/Games/.stage/packages/update.nsp'):
            r'C:\Games\generation\packages\update.nsp',
        Uri.parse('file:///C:/Games/.stage/packages/dlc.nsp'):
            r'C:\Games\generation\packages\dlc.nsp',
      };
      expect(
        relocateSwitchPackagePaths({
          'updates': {
            r'C:\Games/.stage/packages\update.nsp': true,
            'path': r'C:\Games\.stage\packages\update.nsp',
          },
          'dlc': [
            {'path': 'C:/Games/.stage/packages/dlc.nsp', 'enabled': true},
          ],
        }, replacements),
        {
          // Dictionary keys are metadata, not filesystem references.
          'updates': {
            r'C:\Games/.stage/packages\update.nsp': true,
            'path': r'C:\Games\generation\packages\update.nsp',
          },
          'dlc': [
            {'path': r'C:\Games\generation\packages\dlc.nsp', 'enabled': true},
          ],
        },
      );
    },
  );
  test('UNC paths and encoded filename characters relocate without changing unrelated metadata', () {
    final source = Uri.parse(
      'file://server/share/a%20b%231/packages/extra.nsp',
    );
    expect(
      relocateSwitchPackagePaths(
        [
          {'path': r'\\server\share\a b#1\packages\extra.nsp'},
          {
            'path': r'\\server\share\a b#1\packages-other\extra.nsp',
            'title': 'Keep this',
          },
        ],
        {source: r'\\server\share\published\extra.nsp'},
      ),
      [
        {'path': r'\\server\share\published\extra.nsp'},
        {
          'path': r'\\server\share\a b#1\packages-other\extra.nsp',
          'title': 'Keep this',
        },
      ],
    );
  });
}
