import 'package:material_ui/material_ui.dart' hide Title;

import '../app.dart';
import '../core/models.dart';
import '../core/naming.dart';
import 'hud/hud_theme.dart';
import 'menu.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// 一覧の中身（Theta Music Hatch の menus.dart にあたるもの）。棚 → 作品 → シーズン → 話

class ThetaTab {
  final String label; // 縦のタブの文字
  final String title; // モードの一覧での名前
  final IconData icon;
  final int group; // 0 よく使う（accent）・1 ライブラリ（widget）・2 管理（launch）
  final IPodScreen Function() root;
  const ThetaTab(this.label, this.title, this.icon, this.group, this.root);
}

String shelfCode(String shelf) => switch (shelf) {
      '映画' => 'MOVIE',
      'アニメ映画' => 'A.MOVIE',
      'ドラマ' => 'DRAMA',
      'アニメ' => 'ANIME',
      'テレビ' => 'TV',
      'ライブ' => 'LIVE',
      'ホームビデオ' => 'HOME',
      '' => 'OTHER',
      _ => shelf.length > 6 ? shelf.substring(0, 6) : shelf,
    };

IconData _shelfIcon(String shelf) => switch (shelfKindOf(shelf)) {
      ShelfKind.movie => Icons.movie_outlined,
      ShelfKind.series => Icons.video_library_outlined,
      ShelfKind.home => Icons.family_restroom,
      ShelfKind.auto => Icons.folder_outlined,
    };

/// ライブラリが空のときは、どのタブも「読み込み・設定」の案内にする
IPodScreen _lib(IPodScreen Function() f) => services.library.titles.isEmpty ? libraryMenu() : f();

/// モード（左のタブ）。棚は NAS のフォルダから
List<ThetaTab> thetaTabs() => [
      ThetaTab('RESUME', '続きから', Icons.play_circle_outline, 0, () => _lib(resumeMenu)),
      ThetaTab('NEW', '最近追加', Icons.fiber_new_outlined, 0, () => _lib(recentMenu)),
      for (final s in services.library.shelves)
        ThetaTab(shelfCode(s), s.isEmpty ? 'そのほか' : s, _shelfIcon(s), 1, () => shelfMenu(s)),
      ThetaTab('SEARCH', '探す', Icons.search, 0, searchMenu),
      ThetaTab('SETUP', '設定', Icons.tune, 2, libraryMenu),
    ];

/// いちばん上の階層：モードの一覧
MenuScreen modeMenu(void Function(int) open) => MenuScreen(
      'Movie',
      () {
        final tabs = thetaTabs();
        return [
          for (var i = 0; i < tabs.length; i++)
            MenuItem(tabs[i].title,
                chevron: true,
                detail: tabs[i].group == 1 ? '${services.library.onShelf(tabs[i].title == 'そのほか' ? '' : tabs[i].title).length}' : null,
                onSelect: () => open(i)),
        ];
      },
      deps: [services.library],
    );

// ---------------------------------------------------------------- 作品の行

String _year(Title t) => t.displayYear == null ? '' : '${t.displayYear}';

MenuItem titleItem(Title t, {String? detail}) {
  final files = t.allFiles;
  final done = files.isNotEmpty && files.every((f) => services.progress.isDone(f.path));
  return MenuItem(
    t.displayName,
    detail: detail ?? (t.kind == TitleKind.series ? '${t.episodes.length}話' : _year(t)),
    chevron: true,
    thumb: true,
    poster: t.poster,
    starred: done,
    onSelect: () => nav.push(titleMenu(t)),
    onLong: () => _toggleDone(t),
  );
}

void _toggleDone(Title t) {
  final files = t.kind == TitleKind.series ? t.episodes.map((e) => e.file).toList() : t.files;
  final done = files.every((f) => services.progress.isDone(f.path));
  for (final f in files) {
    services.progress.setDone(f.path, !done);
  }
  nav.toast(done ? '「まだ」にしました' : '✓ 見たことにしました');
}

MenuScreen shelfMenu(String shelf) => MenuScreen(
      shelf.isEmpty ? 'そのほか' : shelf,
      () {
        final l = services.library.onShelf(shelf)..sort((a, b) => naturalCompare(a.displayName, b.displayName));
        return [for (final t in l) titleItem(t)];
      },
      deps: [services.library, services.progress],
      letterIndex: true,
    );

MenuScreen resumeMenu() => MenuScreen(
      '続きから',
      () => [
        for (final (t, f, m) in services.progress.continueWatching(services.library.titles))
          MenuItem(
            t.displayName,
            detail: _episodeCode(t, f),
            thumb: true,
            poster: t.poster,
            filePath: f.path,
            progress: m?.ratio ?? 0,
            onSelect: () => services.playback.play(t, f),
            onLong: () => nav.push(titleMenu(t)),
          ),
      ],
      deps: [services.library, services.progress],
    );

String? _episodeCode(Title t, VideoFile f) {
  final e = t.episodes.where((e) => e.file.path == f.path).firstOrNull;
  return e?.code;
}

MenuScreen recentMenu() => MenuScreen(
      '最近追加',
      () => [for (final t in services.library.recentlyAdded) titleItem(t, detail: t.shelf)],
      deps: [services.library, services.progress],
    );

MenuScreen searchMenu() {
  late MenuScreen m;
  var query = '';
  m = MenuScreen(
    '探す',
    () => [
      MenuItem(query.isEmpty ? '文字で探す…' : '「$query」を探し直す…', onSelect: () async {
        final q = await askText(nav.context, '題名・出演者・監督', hint: '例：新海誠');
        if (q == null || q.trim().isEmpty) return;
        query = q.trim();
        m.selected = 1;
        m.refresh();
      }),
      for (final t in services.library.search(query)) titleItem(t, detail: t.shelf),
    ],
    deps: [services.library],
  );
  return m;
}

// ---------------------------------------------------------------- 作品

MenuScreen titleMenu(Title t) => MenuScreen(
      t.displayName,
      () {
        final pr = services.progress;
        final items = <MenuItem>[];
        if (t.kind == TitleKind.series) {
          final next = pr.nextEpisode(t);
          if (next != null) {
            final at = pr.resumeAt(next.file.path);
            items.add(MenuItem('▶ ${at > 0 ? '続きから' : '再生'}  ${next.code} ${next.title}'.trim(),
                detail: at > 0 ? fmtDuration(at) : null,
                poster: t.poster,
                filePath: next.file.path,
                onSelect: () => services.playback.play(t, next.file)));
          }
          final seasons = t.seasons;
          if (seasons.length == 1) {
            items.addAll(_episodeItems(t, seasons.single));
          } else {
            for (final s in seasons) {
              final eps = t.episodesOf(s);
              final done = eps.where((e) => pr.isDone(e.file.path)).length;
              items.add(MenuItem(_seasonName(s),
                  detail: '$done/${eps.length}', chevron: true, poster: t.poster, onSelect: () => nav.push(seasonMenu(t, s))));
            }
          }
        } else {
          for (final f in t.files) {
            final at = pr.resumeAt(f.path);
            final name = f.label.isEmpty ? '' : '（${f.label}）';
            items.add(MenuItem('▶ ${at > 0 ? '続きから' : '再生'}$name',
                detail: at > 0 ? fmtDuration(at) : fmtSize(f.size),
                poster: t.poster,
                filePath: f.path,
                progress: pr.of(f.path)?.ratio ?? 0,
                onSelect: () => services.playback.play(t, f)));
            if (at > 0) {
              items.add(MenuItem('↺ 最初から$name',
                  poster: t.poster, onSelect: () => services.playback.play(t, f, fromStart: true)));
            }
          }
        }
        if (t.info.plot.isNotEmpty || t.info.cast.isNotEmpty || t.info.directors.isNotEmpty) {
          items.add(MenuItem('あらすじ・出演', chevron: true, poster: t.poster, onSelect: () => nav.push(aboutScreen(t))));
        }
        final people = [...t.info.directors, ...t.info.cast.take(12)];
        if (people.isNotEmpty) {
          items.add(MenuItem('出演者・監督', detail: '${people.length}', chevron: true, poster: t.poster, onSelect: () {
            nav.push(MenuScreen('出演者・監督', () => [
                  for (final n in people)
                    MenuItem(n,
                        chevron: true,
                        detail: t.info.directors.contains(n) ? '監督' : null,
                        onSelect: () => nav.push(personMenu(n))),
                ]));
          }));
        }
        if (t.extras.isNotEmpty) {
          items.add(MenuItem('特典映像', detail: '${t.extras.length}', chevron: true, poster: t.poster, onSelect: () {
            nav.push(MenuScreen('特典映像', () => [
                  for (final f in t.extras)
                    MenuItem(f.label.isEmpty ? f.name : f.label,
                        filePath: f.path, onSelect: () => services.playback.play(t, f)),
                ]));
          }));
        }
        final rel = services.library.related(t);
        if (rel.isNotEmpty) {
          items.add(MenuItem('関連作品', detail: '${rel.length}', chevron: true, poster: t.poster, onSelect: () {
            nav.push(MenuScreen('関連作品', () => [for (final o in rel) titleItem(o, detail: o.shelf)]));
          }));
        }
        return items;
      },
      deps: [services.progress],
    );

String _seasonName(int s) => s == 0 ? '特別編' : (s > 1900 ? '$s 年' : 'シーズン $s');

MenuScreen seasonMenu(Title t, int season) =>
    MenuScreen('${t.displayName} ${_seasonName(season)}', () => _episodeItems(t, season), deps: [services.progress]);

List<MenuItem> _episodeItems(Title t, int season) => [
      for (final (i, e) in t.episodesOf(season).indexed)
        MenuItem(
          e.title.isNotEmpty ? '${e.code.isEmpty ? '${i + 1}' : e.code} ${e.title}' : (e.code.isEmpty ? e.file.name : e.code),
          detail: e.tags.isEmpty ? null : e.tags.first,
          starred: services.progress.isDone(e.file.path),
          progress: services.progress.isDone(e.file.path) ? 0 : services.progress.of(e.file.path)?.ratio ?? 0,
          poster: t.poster,
          filePath: e.file.path,
          onSelect: () => services.playback.play(t, e.file),
          onLong: () {
            final done = services.progress.isDone(e.file.path);
            services.progress.setDone(e.file.path, !done);
            nav.toast(done ? '「まだ」にしました' : '✓ 見たことにしました');
          },
        ),
    ];

InfoScreen aboutScreen(Title t) => InfoScreen(
      t.displayName,
      (context) {
        final p = HudScope.of(context);
        final i = t.info;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (i.originalTitle.isNotEmpty) Text(i.originalTitle, style: TextStyle(color: p.muted, fontSize: 12)),
          Text([_year(t), ...i.genres].where((s) => s.isNotEmpty).join(' ・ '),
              style: TextStyle(color: p.accent, fontSize: 12, fontFamily: p.mono)),
          if (i.tagline.isNotEmpty) ...[const SizedBox(height: 8), Text(i.tagline, style: const TextStyle(fontStyle: FontStyle.italic))],
          if (i.plot.isNotEmpty) ...[const SizedBox(height: 8), Text(i.plot)],
          if (i.directors.isNotEmpty) ...[const SizedBox(height: 8), Text('監督 ${i.directors.join('・')}', style: TextStyle(color: p.muted))],
          if (i.cast.isNotEmpty) Text('出演 ${i.cast.take(12).join('・')}', style: TextStyle(color: p.muted)),
        ]);
      },
      image: t.poster,
    );

/// 同じ人が出ている作品
MenuScreen personMenu(String name) => MenuScreen(
      name,
      () => [
        for (final t in services.library.titles)
          if (t.info.cast.contains(name) || t.info.directors.contains(name)) titleItem(t, detail: t.shelf),
      ],
      deps: [services.library],
    );

// ---------------------------------------------------------------- 設定・読み込み

MenuScreen libraryMenu() => MenuScreen(
      '設定',
      () {
        final lib = services.library;
        return [
          MenuItem(lib.scanning ? '読み込み中… ${lib.status}' : 'NAS を読み直す',
              detail: lib.scanning ? null : '${lib.titles.length} 作品', onSelect: () {
            if (lib.scanning) {
              lib.cancel();
            } else {
              lib.scan();
            }
          }),
          if (lib.error != null)
            MenuItem('⚠ ${lib.error}', onSelect: () async {
              if (lib.needOtp) {
                final code = await askOtp(nav.context);
                if (code != null) {
                  lib.setOtp(code);
                  await lib.scan();
                }
              } else if (lib.skipped.isNotEmpty) {
                nav.push(MenuScreen('読めなかったフォルダ', () => [for (final s in lib.skipped) MenuItem(s)]));
              }
            }),
          MenuItem('接続・スキン・ホイールの設定', chevron: true, onSelect: () {
            Navigator.of(nav.context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
          }),
          if (services.playback.hasMedia) MenuItem('再生を止める', onSelect: services.playback.stop),
        ];
      },
      deps: [services.library, services.playback],
    );
