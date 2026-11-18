import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../core/library.dart';
import '../core/series.dart';
import '../core/settings.dart';
import '../core/source.dart';
import 'hud/hud_theme.dart';
import 'hud/hud_widgets.dart';
import 'hud/skins.g.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppSettings _s = AppScope.of(context).settings;
  late final _dsUrl = TextEditingController(text: _s.dsUrl);
  late final _davUrl = TextEditingController(text: _s.davUrl);
  late final _user = TextEditingController(text: _s.user);
  late final _pass = TextEditingController(text: _s.password);
  late final _root = TextEditingController(text: _s.videoRoot);
  late final _prefix = TextEditingController(text: _s.folderPrefix);
  late final Library _lib = AppScope.of(context).library;
  String _hub = '';
  String _version = '';
  String? _latest;
  bool _busy = false;
  String _result = '';

  @override
  void initState() {
    super.initState();
    Series.hub().then((h) => mounted ? setState(() => _hub = h) : null);
    Series.version().then((v) {
      if (mounted) setState(() => _version = v);
      Series.latest().then((l) => mounted ? setState(() => _latest = l) : null);
    });
  }

  Future<void> _apply() async {
    final changed = _s.dsUrl != _dsUrl.text.trim() ||
        _s.davUrl != _davUrl.text.trim() ||
        _s.user != _user.text.trim() ||
        _s.password != _pass.text;
    _s
      ..dsUrl = _dsUrl.text.trim()
      ..davUrl = _davUrl.text.trim()
      ..user = _user.text.trim()
      ..password = _pass.text
      ..videoRoot = _root.text.trim().isEmpty ? '/video' : _s.videoRootsOf(_root.text).join(', ')
      ..folderPrefix = _prefix.text.trim();
    if (changed) _s.did = '';
    await _s.save();
    _lib.resetSource();
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = '';
    });
    final lib = _lib;
    await _apply();
    try {
      await lib.source.check();
      final lines = <String>[];
      final pre = _s.folderPrefix.trim().toLowerCase();
      for (final root in _s.videoRoots) {
        final dirs = (await lib.source.list(root)).where((e) => e.isDir).toList();
        if (pre.isEmpty) {
          lines.add('$root：フォルダ ${dirs.length} 個（全部を読む）');
        } else {
          final hit = [for (final d in dirs) if (d.name.toLowerCase().startsWith(pre)) d.name];
          lines.add('$root：「${_s.folderPrefix.trim()}」のフォルダ ${hit.length} 個'
              '${hit.isEmpty ? '' : '（${hit.take(8).join('・')}${hit.length > 8 ? '…' : ''}）'}');
        }
      }
      _result = 'つながりました\n${lines.join('\n')}';
    } on OtpRequired catch (e) {
      if (!mounted) return;
      final code = await askOtp(context);
      if (code != null) {
        lib.setOtp(code);
        setState(() => _busy = false);
        return _test();
      }
      _result = e.message;
    } catch (e) {
      _result = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Theta Home Hatch（設定のハブ）の NAS の設定を使う（THETA_SHARED_SETTINGS.md §4.1）
  Future<void> _fromHub() async {
    final info = await Series.info();
    try {
      final url = info['nas.url'] ?? '';
      final user = info['nas.user'] ?? '';
      final pass = await Series.secret('nas.password');
      final token = await Series.secret('nas.deviceToken');
      setState(() {
        if (url.isNotEmpty) _dsUrl.text = url;
        if (user.isNotEmpty) _user.text = user;
        if (pass.isNotEmpty) _pass.text = pass;
      });
      await _apply();
      if (token.isNotEmpty) {
        _s.did = token;
        await _s.save();
      }
      if (mounted) toast(context, 'Home Hatch の NAS の設定を受け取りました');
    } catch (e) {
      if (mounted) toast(context, '受け取れませんでした：$e');
    }
  }

  /// 音が出ない・再生できないときの手がかり（mpv の警告・エラーと、今の音声の様子）
  Future<void> _showLog() async {
    final info = await services.playback.audioInfo();
    final lines = services.playback.log.reversed.take(120).toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('再生のログ'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              '$info\n\n${lines.isEmpty ? '（警告・エラーはありません）' : lines.join('\n')}',
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$info\n\n${lines.join('\n')}'));
              Navigator.of(ctx).pop();
            },
            child: const Text('コピー'),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('閉じる')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _apply();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final services = AppScope.of(context);
    _lib; // dispose で使うので先に取っておく
    InputDecoration deco(String label, [String? hint]) =>
        InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(backgroundColor: p.bg, foregroundColor: p.fg, title: const Text('設定')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        HudPanel(
          code: 'NAS',
          title: '動画の読み先',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<SourceKind>(
              segments: const [
                ButtonSegment(value: SourceKind.dsm, label: Text('File Station（おすすめ）')),
                ButtonSegment(value: SourceKind.webdav, label: Text('WebDAV')),
              ],
              selected: {_s.source},
              onSelectionChanged: (v) async {
                _s.source = v.first;
                await _apply();
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            if (_s.source == SourceKind.dsm)
              TextField(controller: _dsUrl, decoration: deco('DSM の URL', 'http://nas.tailXXXX.ts.net:5000'))
            else
              TextField(controller: _davUrl, decoration: deco('WebDAV の URL', 'http://nas.tailXXXX.ts.net:5005')),
            const SizedBox(height: 10),
            TextField(controller: _user, decoration: deco('ユーザー名')),
            const SizedBox(height: 10),
            TextField(controller: _pass, obscureText: true, decoration: deco('パスワード')),
            const SizedBox(height: 10),
            TextField(controller: _root, decoration: deco('動画の共有フォルダ（複数はカンマで）', '/video')),
            const SizedBox(height: 10),
            TextField(controller: _prefix, decoration: deco('読むフォルダの目印（空なら全部）', '⑧')),
            const SizedBox(height: 4),
            Text(
              '共有フォルダの直下で、名前が目印で始まるフォルダだけを読みます（Theta Book Hatch と同じ）。'
              '例：⑧映画・⑧アニメ → 棚「映画」「アニメ」',
              style: TextStyle(color: p.faint, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              PillButton(icon: Icons.wifi_tethering, text: '接続を確かめる', primary: true, onTap: _busy ? null : _test),
              if (_hub.isNotEmpty) PillButton(icon: Icons.home, text: 'Home Hatch の設定を使う', onTap: _fromHub),
            ]),
            if (_busy) Padding(padding: const EdgeInsets.only(top: 12), child: LinearProgressIndicator(color: p.accent)),
            if (_result.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(_result, style: TextStyle(color: p.muted))),
            const SizedBox(height: 8),
            Text(
              '外からは Tailscale で。2 段階認証（Secure SignIn）は File Station のときに使えます。'
              '確認コードを 1 回入れれば、この端末は次から要りません。',
              style: TextStyle(color: p.faint, fontSize: 11, height: 1.5),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        HudPanel(
          code: 'SKIN',
          title: 'スキン',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('シリーズに合わせる（Home Hatch と同じ）'),
              value: _s.followSeriesSkin,
              onChanged: (v) async {
                _s.followSeriesSkin = v;
                await _s.save();
                if (v) await services.followHub();
                setState(() {});
              },
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in skinNames)
                ChoiceChip(
                  label: Text(k == 'system' ? '端末に合わせる' : skinLabels[k] ?? k),
                  selected: _s.skin == k,
                  onSelected: (_) async {
                    _s.skin = k;
                    await _s.save();
                    if (_s.followSeriesSkin) await Series.tell('ui.skin', k);
                    setState(() {});
                  },
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        HudPanel(
          code: 'AUDIO',
          title: '音',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'audiotrack', label: Text('AudioTrack')),
                ButtonSegment(value: 'opensles', label: Text('OpenSL ES')),
              ],
              selected: {_s.audioOutput},
              onSelectionChanged: (v) async {
                _s.audioOutput = v.first;
                await _s.save();
                await services.playback.applyAudioOutput();
                setState(() {});
              },
            ),
            const SizedBox(height: 4),
            Text('音が出ないときは、もう一方に切り替えてみてください（再生中でも切り替わります）。それでも出なければ「再生のログ」をコピーして送ってください',
                style: TextStyle(color: p.faint, fontSize: 11, height: 1.5)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: PillButton(icon: Icons.receipt_long, text: '再生のログ', onTap: _showLog),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        HudPanel(
          code: 'LAYOUT',
          title: '画面の並べ方',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'auto', label: Text('自動')),
                ButtonSegment(value: 'wide', label: Text('横並び')),
                ButtonSegment(value: 'tall', label: Text('縦並び')),
              ],
              selected: {_s.thetaLayout},
              onSelectionChanged: (v) async {
                _s.thetaLayout = v.first;
                await _s.save();
                setState(() {});
              },
            ),
            const SizedBox(height: 4),
            Text('自動：幅 600 以上で、幅が高さの 3/4 以上なら横並び（Z Fold を広げたとき・タブレットの横）',
                style: TextStyle(color: p.faint, fontSize: 11, height: 1.5)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('左のタブに名前を出す'),
              value: _s.tabLabels,
              onChanged: (v) async {
                _s.tabLabels = v;
                await _s.save();
                setState(() {});
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),
        HudPanel(
          code: 'WHEEL',
          title: 'ホイール',
          child: Column(children: [
            for (final (label, get, set) in <(String, bool Function(), void Function(bool))>[
              ('カリカリ音', () => _s.clicker, (v) => _s.clicker = v),
              ('振動', () => _s.haptics, (v) => _s.haptics = v),
              ('ボタンの案内（押すと何が起きるか）', () => _s.wheelGuide, (v) => _s.wheelGuide = v),
            ])
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                value: get(),
                onChanged: (v) async {
                  set(v);
                  await _s.save();
                  setState(() {});
                },
              ),
          ]),
        ),
        const SizedBox(height: 16),
        HudPanel(
          code: 'DATA',
          title: 'キャッシュ',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            PillButton(
              icon: Icons.sync,
              text: 'NAS を読み直す',
              onTap: () {
                services.library.scan();
                Navigator.of(context).maybePop();
              },
            ),
            PillButton(
              icon: Icons.image_not_supported,
              text: 'ポスターを取り直す',
              onTap: () async {
                await services.posters.clear();
                if (context.mounted) toast(context, 'ポスターのキャッシュを消しました');
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),
        HudPanel(
          code: 'VER',
          title: 'この版',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Theta Movie Hatch $_version', style: TextStyle(color: p.fg, fontFamily: p.mono)),
            if (_latest != null && Series.newer(_latest!, _version))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('新しい版 $_latest があります', style: TextStyle(color: p.accent)),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: PillButton(
                icon: Icons.system_update,
                text: _hub.isEmpty ? 'Releases を開く' : '更新する（Home Hatch に頼む）',
                onTap: Series.requestUpdate,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
