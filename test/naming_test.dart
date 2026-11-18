import 'package:flutter_test/flutter_test.dart';
import 'package:theta_movie/core/naming.dart';

void main() {
  group('作品フォルダの名前', () {
    test('タイトル (年)', () {
      final t = parseTitleName('君の名は。 (2016)');
      expect(t.title, '君の名は。');
      expect(t.year, 2016);
    });
    test('ID 付き・全角かっこ・補足', () {
      final t = parseTitleName('〇〇 (2010) [tmdbid-12345]');
      expect(t.title, '〇〇');
      expect(t.year, 2010);
      expect(t.tmdbId, '12345');
      expect(parseTitleName('七人の侍（1954）').year, 1954);
      expect(parseTitleName('作品 (2001) [DVD]').title, '作品');
    });
    test('年の無い名前はそのまま', () {
      final t = parseTitleName('2001年宇宙の旅');
      expect(t.title, '2001年宇宙の旅');
      expect(t.year, isNull);
    });
  });

  group('映画のファイル', () {
    test('バージョンとパート', () {
      expect(parseMovieFile('君の名は。 (2016) - 4K.mkv').version, '4K');
      expect(parseMovieFile('七人の侍 (1954) - part2.mkv').part, 2);
      expect(parseMovieFile('君の名は。 (2016).mkv').version, '');
    });
  });

  group('シーズンのフォルダ', () {
    test('規則と、よくある別の書き方', () {
      expect(parseSeasonFolder('Season 01'), 1);
      expect(parseSeasonFolder('Season 2019'), 2019);
      expect(parseSeasonFolder('Season 00'), 0);
      expect(parseSeasonFolder('Specials'), 0);
      expect(parseSeasonFolder('第2期'), 2);
      expect(parseSeasonFolder('シーズン3'), 3);
      expect(parseSeasonFolder('extras'), isNull);
    });
    test('タイトル付きのシーズンのフォルダ（整理前）', () {
      expect(parseSeasonFolder('Season 02 遊郭編'), 2);
      expect(seasonFolderTitle('Season 02 遊郭編'), '遊郭編');
      expect(seasonFolderTitle('Season 2 - 遊郭編'), '遊郭編');
      expect(parseSeasonFolder('第2期 遊郭編'), 2);
      expect(seasonFolderTitle('第2期 遊郭編'), '遊郭編');
      expect(seasonFolderTitle('Season 01'), '');
      expect(parseSeasonFolder('S2ample'), isNull);
    });
  });

  group('話のファイル', () {
    test('規則どおり', () {
      final e = parseEpisodeFile('〇〇 S01E03「サブタイトル」 [2019-04-21 TBS].ts');
      expect(e.season, 1);
      expect(e.episode, 3);
      expect(e.subtitle, 'サブタイトル');
      expect(e.tags, ['2019-04-21 TBS']);
      expect(e.airDate, DateTime(2019, 4, 21));
    });
    test('2 話入り', () {
      final e = parseEpisodeFile('〇〇 S01E03-E04.mkv');
      expect(e.episode, 3);
      expect(e.episodeEnd, 4);
    });
    test('放送日の番組', () {
      final e = parseEpisodeFile('〇〇の番組 2019-04-07「今回の内容」 [テレ朝].ts');
      expect(e.episode, isNull);
      expect(e.airDate, DateTime(2019, 4, 7));
      expect(e.subtitle, '今回の内容');
    });
    test('整理前の名前', () {
      expect(parseEpisodeFile('ドラマ名 第5話.mp4').episode, 5);
      expect(parseEpisodeFile('ドラマ名 #12「題」.ts').episode, 12);
      expect(parseEpisodeFile('Show.Name.S02E10.1080p.mkv').season, 2);
      expect(parseEpisodeFile('Show.Name.S02E10.1080p.mkv').episode, 10);
      expect(parseEpisodeFile('anime ep07.mkv').episode, 7);
      expect(parseEpisodeFile('映画のタイトル.mkv').hasNumber, isFalse);
    });
  });

  test('自然な並び', () {
    final l = ['第10話.mkv', '第2話.mkv', '第1話.mkv']..sort(naturalCompare);
    expect(l, ['第1話.mkv', '第2話.mkv', '第10話.mkv']);
  });

  test('隠しフォルダと動画', () {
    expect(isHiddenName('@eaDir'), isTrue);
    expect(isHiddenName('#recycle'), isTrue);
    expect(isHiddenName('_未整理'), isTrue);
    expect(isVideo('a.MKV'), isTrue);
    expect(isVideo('a.nfo'), isFalse);
  });
}
