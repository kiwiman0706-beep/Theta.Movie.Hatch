import 'package:material_ui/material_ui.dart' hide Title;

import '../app.dart';
import '../core/models.dart';
import 'hud/hud_theme.dart';
import 'hud/hud_widgets.dart';
import 'player_screen.dart';
import 'widgets.dart';

/// 作品の画面：ポスター・あらすじ・再生（続きから）・シーズンと話・特典・関連
class TitleScreen extends StatefulWidget {
  final String titleId;
  const TitleScreen({super.key, required this.titleId});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = HudScope.of(context);
    final t = s.library.byId(widget.titleId);
    if (t == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('見つかりません（NAS を読み直してください）')));
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: ListenableBuilder(
        listenable: s.progress,
        builder: (context, _) => CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: t.fanart == null ? null : 200,
            backgroundColor: p.bg,
            foregroundColor: p.fg,
            title: Text(t.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
            flexibleSpace: t.fanart == null
                ? null
                : FlexibleSpaceBar(
                    background: Stack(fit: StackFit.expand, children: [
                      NasImage(t.fanart),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, p.bg],
                          ),
                        ),
                      ),
                    ]),
                  ),
          ),
          SliverToBoxAdapter(child: _head(context, p, t)),
          if (t.kind == TitleKind.series) ..._episodes(context, p, t),
          if (t.files.length > 1) SliverToBoxAdapter(child: _versions(context, p, t)),
          if (t.extras.isNotEmpty) SliverToBoxAdapter(child: _extras(context, p, t)),
          SliverToBoxAdapter(child: _related(context, t)),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ]),
      ),
    );
  }

  Widget _head(BuildContext context, Palette p, Title t) {
    final s = AppScope.of(context);
    final info = t.info;
    final y = t.displayYear;
    final (VideoFile? file, String label) = _primary(context, t);
    final resume = file == null ? 0 : s.progress.resumeAt(file.path);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 120,
            child: AspectRatio(aspectRatio: 2 / 3, child: NasImage(t.poster, fallback: t.displayName)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.displayName, style: TextStyle(color: p.fg, fontSize: 18, fontWeight: FontWeight.w600)),
              if (info.originalTitle.isNotEmpty && info.originalTitle != t.displayName)
                Text(info.originalTitle, style: TextStyle(color: p.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (y != null) HudBadge('$y', width: 52),
                HudBadge(t.shelf.isEmpty ? 'LIB' : t.shelf, width: 76),
                if (t.kind == TitleKind.series) HudBadge('${t.episodes.length} 話', width: 60),
                for (final g in info.genres.take(3)) HudBadge(g, width: 76),
              ]),
              if (info.directors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('監督 ${info.directors.join('・')}', style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        if (file != null)
          Row(children: [
            Expanded(
              child: PillButton(
                icon: Icons.play_arrow,
                text: resume > 0 ? '続きから（${fmtDuration(resume)}）' : label,
                primary: true,
                minHeight: 48,
                onTap: () => PlayerScreen.open(context, t, file),
              ),
            ),
            if (resume > 0) ...[
              const SizedBox(width: 8),
              PillButton(
                icon: Icons.replay,
                text: '最初から',
                minHeight: 48,
                onTap: () => PlayerScreen.open(context, t, file, fromStart: true),
              ),
            ],
          ]),
        if (info.tagline.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(info.tagline, style: TextStyle(color: p.fg, fontSize: 14, fontStyle: FontStyle.italic)),
        ],
        if (info.plot.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(info.plot, style: TextStyle(color: p.muted, fontSize: 13, height: 1.6)),
        ],
        if (info.cast.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('出演 ${info.cast.take(10).join('・')}', style: TextStyle(color: p.faint, fontSize: 12, height: 1.5)),
        ],
      ]),
    );
  }

  /// 主な再生ボタン：映画は本編、シリーズは次に見る話
  (VideoFile?, String) _primary(BuildContext context, Title t) {
    if (t.kind == TitleKind.series) {
      final e = AppScope.of(context).progress.nextEpisode(t);
      if (e == null) return (null, '');
      return (e.file, '${e.code.isEmpty ? '' : '${e.code} '}を再生');
    }
    if (t.files.isEmpty) return (null, '');
    return (t.files.first, '再生');
  }

  List<Widget> _episodes(BuildContext context, Palette p, Title t) {
    final seasons = t.seasons;
    if (seasons.isEmpty) return const [];
    final s = AppScope.of(context);
    final cur = _season != null && seasons.contains(_season) ? _season! : (s.progress.nextEpisode(t)?.season ?? seasons.first);
    final eps = t.episodesOf(cur);
    return [
      if (seasons.length > 1)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final n in seasons)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(n == 0 ? '特別編' : (n > 1900 ? '$n 年' : 'シーズン $n')),
                      selected: n == cur,
                      onSelected: (_) => setState(() => _season = n),
                    ),
                  ),
              ],
            ),
          ),
        ),
      SliverList.builder(
        itemCount: eps.length,
        itemBuilder: (context, i) {
          final e = eps[i];
          final m = s.progress.of(e.file.path);
          final done = m?.done ?? false;
          return HudRow(
            zebra: i,
            onTap: () => PlayerScreen.open(context, t, e.file),
            onLongPress: () => s.progress.setDone(e.file.path, !done),
            child: Row(children: [
              SizedBox(
                width: 72,
                child: Text(e.code.isEmpty ? '${i + 1}' : e.code,
                    style: TextStyle(color: done ? p.faint : p.accent, fontSize: 12, fontFamily: p.mono)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title.isNotEmpty ? e.title : e.file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: done ? p.faint : p.fg, fontSize: 13)),
                  if (e.tags.isNotEmpty)
                    Text(e.tags.join(' '), style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono)),
                  if (m != null && !done && m.ratio > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(value: m.ratio, minHeight: 3, color: p.accent, backgroundColor: p.line),
                    ),
                ]),
              ),
              Icon(done ? Icons.check_circle : Icons.play_circle_outline, color: done ? p.accent : p.muted, size: 22),
            ]),
          );
        },
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text('長押しで「見た／まだ」を切り替え', style: TextStyle(color: p.faint, fontSize: 11)),
        ),
      ),
    ];
  }

  Widget _versions(BuildContext context, Palette p, Title t) => Padding(
        padding: const EdgeInsets.all(16),
        child: HudPanel(
          code: 'FILES',
          title: 'バージョン・パート',
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final (i, f) in t.files.indexed)
              HudRow(
                zebra: i,
                onTap: () => PlayerScreen.open(context, t, f),
                child: Row(children: [
                  Expanded(child: Text(f.label.isEmpty ? '本編' : f.label, style: TextStyle(color: p.fg))),
                  Text(fmtSize(f.size), style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono)),
                ]),
              ),
          ]),
        ),
      );

  Widget _extras(BuildContext context, Palette p, Title t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: HudPanel(
          code: 'EXTRA',
          title: '特典映像',
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final (i, f) in t.extras.indexed)
              HudRow(
                zebra: i,
                onTap: () => PlayerScreen.open(context, t, f),
                child: Text(f.label.isEmpty ? f.name : f.label, style: TextStyle(color: p.fg)),
              ),
          ]),
        ),
      );

  Widget _related(BuildContext context, Title t) {
    final r = AppScope.of(context).library.related(t);
    if (r.isEmpty) return const SizedBox.shrink();
    return PosterRow(code: 'LINK', label: '同じ出演者・シリーズ', children: [for (final o in r) PosterTile(title: o)]);
  }
}
