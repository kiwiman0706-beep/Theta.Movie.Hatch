import 'package:flutter_test/flutter_test.dart';
import 'package:theta_movie/core/progress.dart';

void main() {
  test('整理の記録（CSV）を読む：見出し・引用符・NAS のパスでない行', () {
    final m = parseRenameLog('\uFEFF元の場所,新しい場所,理由\n'
        '/8Tube/録画/ドラマ名 第1話.ts,"/8Tube/▶ドラマ/ドラマ名 (2019)/Season 01/ドラマ名 S01E01, 前編.ts",話数\n'
        'Z:\\8Tube\\x.mkv,Z:\\8Tube\\y.mkv\n'
        '/8Tube/旧アニメ,/8Tube/▶アニメ/〇〇 (2019),フォルダごと\n');
    expect(m, [
      ('/8Tube/録画/ドラマ名 第1話.ts', '/8Tube/▶ドラマ/ドラマ名 (2019)/Season 01/ドラマ名 S01E01, 前編.ts'),
      ('/8Tube/旧アニメ', '/8Tube/▶アニメ/〇〇 (2019)'),
    ]);
  });

  test('ファイルそのもの・フォルダごとの移動、続けて当てる', () {
    final moves = [
      ('/8Tube/旧アニメ', '/8Tube/▶アニメ/〇〇 (2019)'),
      ('/8Tube/▶アニメ/〇〇 (2019)/01.mkv', '/8Tube/▶アニメ/〇〇 (2019)/Season 01/〇〇 S01E01.mkv'),
    ];
    expect(remapPath('/8Tube/旧アニメ/01.mkv', moves), '/8Tube/▶アニメ/〇〇 (2019)/Season 01/〇〇 S01E01.mkv');
    expect(remapPath('/8Tube/旧アニメ/02.mkv', moves), '/8Tube/▶アニメ/〇〇 (2019)/02.mkv');
    expect(remapPath('/8Tube/旧アニメ2/01.mkv', moves), '/8Tube/旧アニメ2/01.mkv'); // 名前が似ているだけのフォルダは動かさない
    // 元に戻した記録（逆向き）を当てると戻る
    final undo = [for (final (a, b) in moves.reversed) (b, a)];
    expect(remapPath(remapPath('/8Tube/旧アニメ/01.mkv', moves), undo), '/8Tube/旧アニメ/01.mkv');
  });
}
