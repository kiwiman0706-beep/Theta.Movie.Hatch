import 'package:material_ui/material_ui.dart' hide Title;

import '../app.dart';
import '../core/models.dart';
import 'hud/hud_theme.dart';
import 'hud/hud_widgets.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'shelf_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final s = AppScope.of(context);
    // 初めて（キャッシュが無い）ならスキャン、無ければ設定へ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!s.settings.configured) {
        _openSettings();
      } else if (s.library.titles.isEmpty) {
        s.library.scan();
      }
    });
  }

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = HudScope.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([s.library, s.progress]),
          builder: (context, _) {
            final lib = s.library;
            final cw = s.progress.continueWatching(lib.titles);
            return RefreshIndicator(
              onRefresh: lib.scan,
              color: p.accent,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _header(context, p),
                  if (lib.scanning || lib.error != null) _status(context, p),
                  if (!s.settings.configured)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: HudPanel(
                        code: 'SETUP',
                        title: 'NAS につなぐ',
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('NAS の URL・ユーザー名・パスワードを入れてください。Theta Home Hatch が入っていれば、そこから受け取れます。',
                              style: TextStyle(color: p.muted, fontSize: 13)),
                          const SizedBox(height: 12),
                          PillButton(text: '設定を開く', icon: Icons.settings, primary: true, onTap: _openSettings),
                        ]),
                      ),
                    ),
                  if (cw.isNotEmpty)
                    PosterRow(code: 'RESUME', label: '続きから見る', children: [
                      for (final (t, f, m) in cw)
                        PosterTile(
                          title: t,
                          mark: m,
                          subtitle: _cwLabel(t, f),
                          onTap: () => PlayerScreen.open(context, t, f),
                        ),
                    ]),
                  if (lib.recentlyAdded.isNotEmpty)
                    PosterRow(code: 'NEW', label: '最近追加', children: [
                      for (final t in lib.recentlyAdded.take(15)) PosterTile(title: t),
                    ]),
                  for (final shelf in lib.shelves)
                    PosterRow(
                      code: _code(shelf),
                      label: shelf.isEmpty ? 'そのほか' : shelf,
                      onMore: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => ShelfScreen(shelf: shelf))),
                      children: [for (final t in lib.onShelf(shelf).take(20)) PosterTile(title: t)],
                    ),
                  if (s.settings.configured && lib.titles.isEmpty && !lib.scanning && lib.error == null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('動画が見つかりません。設定の「動画のフォルダ」（今は ${s.settings.videoRoot}）を確かめてください。',
                          style: TextStyle(color: p.muted)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _cwLabel(Title t, VideoFile f) {
    if (t.kind != TitleKind.series) return '続きから';
    final e = t.episodes.where((e) => e.file.path == f.path).firstOrNull;
    return e == null ? '' : '${e.code} ${e.title}'.trim();
  }

  static String _code(String shelf) => switch (shelf) {
        '映画' => 'MOVIE',
        'アニメ映画' => 'ANIME.M',
        'ドラマ' => 'DRAMA',
        'アニメ' => 'ANIME',
        'テレビ' => 'TV',
        'ライブ' => 'LIVE',
        'ホームビデオ' => 'HOME',
        _ => 'LIB',
      };

  Widget _header(BuildContext context, Palette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('THETA MOVIE HATCH',
                style: TextStyle(color: p.fg, fontSize: 20, letterSpacing: 2, fontFamily: p.display)),
            const SizedBox(height: 4),
            Stripes(color: p.accent),
          ]),
        ),
        IconButton(
          tooltip: '探す',
          icon: Icon(Icons.search, color: p.fg),
          onPressed: () => showSearch(context: context, delegate: _Search()),
        ),
        IconButton(
          tooltip: 'NAS を読み直す',
          icon: Icon(Icons.sync, color: p.fg),
          onPressed: () => AppScope.of(context).library.scan(),
        ),
        IconButton(tooltip: '設定', icon: Icon(Icons.settings, color: p.fg), onPressed: _openSettings),
      ]),
    );
  }

  Widget _status(BuildContext context, Palette p) {
    final lib = AppScope.of(context).library;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: lib.scanning
          ? Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(lib.status,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12))),
              TextButton(onPressed: lib.cancel, child: const Text('中止')),
            ])
          : ReadoutBox(lib.needOtp ? '2 段階認証' : 'エラー', lib.error ?? '', accent: true).withTap(() async {
              if (lib.needOtp) {
                final code = await askOtp(context);
                if (code != null) {
                  lib.setOtp(code);
                  await lib.scan();
                }
              } else if (lib.skipped.isNotEmpty) {
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('読めなかったフォルダ（${lib.skipped.length}）'),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: ListView(shrinkWrap: true, children: [
                        for (final s in lib.skipped)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(s, style: const TextStyle(fontSize: 12)),
                          ),
                      ]),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('閉じる')),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          lib.scan();
                        },
                        child: const Text('もう一度読む'),
                      ),
                    ],
                  ),
                );
              } else {
                _openSettings();
              }
            }),
    );
  }
}

extension on Widget {
  Widget withTap(VoidCallback onTap) => InkWell(onTap: onTap, child: this);
}

/// 確認コード（Secure SignIn）の入力
Future<String?> askOtp(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('2 段階認証'),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '確認コード（6 桁）'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('やめる')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('ログイン')),
      ],
    ),
  );
}

class _Search extends SearchDelegate<void> {
  _Search() : super(searchFieldLabel: '題名・出演者・監督');

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context);

  @override
  List<Widget> buildActions(BuildContext context) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final r = AppScope.of(context).library.search(query);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140, childAspectRatio: 0.52, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: r.length,
      itemBuilder: (_, i) => PosterTile(title: r[i], subtitle: r[i].shelf),
    );
  }
}
