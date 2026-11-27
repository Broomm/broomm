import 'dart:io';

import 'package:broomm/src/cemu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'Cemu settings preserve unrelated nested preferences and escape paths',
    () {
      final text = patchCemuSettings(
        '''<?xml version="1.0"?><content>
<!-- native preference --><Graphic><VSync>2</VSync></Graphic>
<check_update>true</check_update><mlc_path>old</mlc_path></content>''',
        {
          'check_update': false,
          'mlc_path': '/private/A&B/<game>',
          'pad_size': <String, Object>{'x': 1600, 'y': 900},
        },
      );
      final root = cemuXml(text, 'content').rootElement;
      expect(root.getElement('Graphic')!.getElement('VSync')!.innerText, '2');
      expect(root.getElement('mlc_path')!.innerText, '/private/A&B/<game>');
      expect(root.getElement('check_update')!.innerText, 'false');
      expect(root.getElement('pad_size')!.getElement('y')!.innerText, '900');
      expect(text, contains('native preference'));
      for (final invalid in [
        '<content><check_update>1</check_update><check_update>0</check_update></content>',
        '<content><check_update><nested/></check_update></content>',
        '<!DOCTYPE content [<!ENTITY value SYSTEM "file:///private/no">]><content/>',
        '<other/>',
      ]) {
        expect(
          () => patchCemuSettings(invalid, {'check_update': false}),
          throwsFormatException,
        );
      }
    },
  );

  test('Cemu catalogue binds one base title to the exact selected archive', () {
    const archive = '/library/α & β.wua';
    const entries = '''<title_list>
<title titleId="0005000010101000"><path>/library/α &amp; β.wua</path></title>
<title titleId="0005000e10101000"><path>/library/α &amp; β.wua</path></title>
<title titleId="0005000c10101000"><path>/library/α &amp; β.wua</path></title>
<title titleId="0005000010102000"><path>/other/α &amp; β.wua</path></title>
</title_list>''';
    expect(cemuCatalogueTitle(entries, archive), '0005000010101000');
    expect(
      () => cemuCatalogueTitle(entries, '/missing/α & β.wua'),
      throwsFormatException,
    );
    expect(
      () => cemuCatalogueTitle(
        entries.replaceFirst(
          '</title_list>',
          '<title titleId="0005000010103000"><path>/library/α &amp; β.wua</path></title></title_list>',
        ),
        archive,
      ),
      throwsFormatException,
    );
  });

  test(
    'decrypted Cemu title metadata must agree before choosing a save tree',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'broomm-cemu-metadata-',
      );
      try {
        await Directory('${temp.path}/code').create();
        await Directory('${temp.path}/meta').create();
        final rom = File('${temp.path}/code/game.rpx');
        await rom.writeAsBytes([0x7f, 69, 76, 70]);
        await File('${temp.path}/code/app.xml')
            .writeAsString('<app><title_id>0005000010101000</title_id></app>');
        final meta = File('${temp.path}/meta/meta.xml');
        await meta.writeAsString(
          '<menu><title_id>0005000010101000</title_id></menu>',
        );
        expect(await cemuRpxTitle(rom.path), '0005000010101000');
        await meta.writeAsString(
          '<menu><title_id>0005000010102000</title_id></menu>',
        );
        await expectLater(cemuRpxTitle(rom.path), throwsFormatException);
        await meta.writeAsString(
          '<menu><title_id>0005000e10101000</title_id></menu>',
        );
        await expectLater(cemuRpxTitle(rom.path), throwsFormatException);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
}
