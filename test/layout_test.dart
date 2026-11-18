import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theta_movie/app.dart';
import 'package:theta_movie/core/library.dart';
import 'package:theta_movie/core/models.dart';
import 'package:theta_movie/core/progress.dart';
import 'package:theta_movie/core/settings.dart';

/// 本物の画面（Shell）を、スマホ縦・Z Fold を広げたとき・タブレット横の大きさで描いて、はみ出しが無いかを見る。
/// SHOTS=<フォルダ> を付けて動かすと、画面の PNG をそこに書く（見た目の確認用）
void main() {
  final shots = Platform.environment['SHOTS'];

  setUpAll(() async {
    // 書体（無くても動くが、スクリーンショットを読めるように）
    Future<void> font(String family, List<String> files) async {
      final l = FontLoader(family);
      for (final f in files) {
        final file = File(f);
        if (file.existsSync()) l.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
      await l.load();
    }

    await font('Oswald', ['assets/fonts/oswald_regular.ttf']);
    // 日本語（テストの既定の書体）。CI に無ければ四角になるだけ
    await font('ShareTechMono', ['assets/fonts/share_tech_mono.ttf', '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf']);
  });

  Future<void> setUpServices({int shelves = 12}) async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.secure = null;
    final s = AppSettings();
    await s.load();
    s
      ..dsUrl = 'nas:5000'
      ..user = 'u'
      ..password = 'p'
      ..skin = 'scifi';
    final lib = Library(s);
    final names = ['映画', 'アニメ', 'ドラマ', '子供番組・知育・受験', 'ドキュメンタリー', 'ライブ', '音楽PV', 'スポーツ', '旅', '料理', '教養', 'ニュース'];
    lib.titles = [
      for (var i = 0; i < shelves; i++)
        for (var j = 0; j < 6; j++)
          Title(
            id: '/8Tube/${names[i % names.length]}$i/作品$j',
            shelf: '${names[i % names.length]}${i >= names.length ? i : ''}',
            kind: j.isEven ? TitleKind.movie : TitleKind.series,
            name: 'ねこねこ日本史 その$j',
            year: 2016 + j,
            files: [VideoFile('/8Tube/x$i/$j.mkv', 1000)],
            added: 1000 + i * 10 + j,
          ),
    ];
    services = Services(s, lib, Progress());
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
    late final ui.Image image;
    await tester.runAsync(() async => image = await boundary.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
    File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  for (final (name, size) in [
    ('phone', const Size(412, 915)),
    ('fold_open', const Size(884, 1010)),
    ('tablet_landscape', const Size(1280, 800)),
  ]) {
    testWidgets('はみ出さない：$name', (tester) async {
      await setUpServices();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const RepaintBoundary(key: Key('shot'), child: MovieApp()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await shoot(tester, '${name}_list');
      // MENU で上へ：モードの一覧（左のタブの代わりに、名前の読めるメニュー）
      final back = find.byTooltip('戻る（MENU）');
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(tester.takeException(), isNull);
      await shoot(tester, '${name}_modes');
    });
  }
}
