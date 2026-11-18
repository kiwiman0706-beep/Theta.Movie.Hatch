import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dsm.dart';
import 'models.dart';
import 'progress.dart';
import 'scanner.dart';
import 'settings.dart';
import 'source.dart';
import 'webdav.dart';

/// ライブラリ（作品の一覧）。端末の library.json はキャッシュで、正本は NAS のファイルと .nfo
class Library extends ChangeNotifier {
  final AppSettings settings;
  Library(this.settings);

  MediaSource? _source;
  List<Title> titles = const [];
  bool scanning = false;
  String status = '';
  String? error;
  bool needOtp = false;
  int scannedAt = 0;

  MediaSource get source => _source ??= switch (settings.source) {
        SourceKind.dsm => DsmSource(settings),
        SourceKind.webdav => WebDavSource(settings),
      };

  /// 接続先を変えたら呼ぶ
  void resetSource() {
    _source?.close();
    _source = null;
  }

  void setOtp(String code) {
    final s = source;
    if (s is DsmSource) s.setOtp(code);
  }

  Future<File> _cacheFile() async => File('${(await getApplicationSupportDirectory()).path}/library.json');

  Future<void> loadCache() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['root'] != _scope) return;
      titles = [for (final t in (j['titles'] as List)) Title.fromJson(t as Map<String, dynamic>)];
      scannedAt = j['at'] as int? ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('library cache: $e');
    }
  }

  Future<void> _saveCache() async {
    final f = await _cacheFile();
    await f.writeAsString(jsonEncode({
      'root': _scope,
      'at': scannedAt,
      'titles': [for (final t in titles) t.toJson()],
    }));
  }

  /// キャッシュの対象（読む場所と目印が変わったら読み直す）
  String get _scope => '${settings.videoRoots.join(',')}|${settings.folderPrefix.trim()}';

  bool _cancel = false;
  void cancel() => _cancel = true;

  /// 読めなかったフォルダ（スキャンは止めずに続けた）
  List<String> skipped = const [];

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    error = null;
    needOtp = false;
    _cancel = false;
    skipped = const [];
    status = 'NAS につないでいます…';
    notifyListeners();
    final firstTime = titles.isEmpty;
    var lastShown = 0;
    try {
      final src = source;
      await src.check();
      late final Scanner sc;
      sc = Scanner(src.list, src.read,
          onProgress: (dir, n) {
            status = '$n 作品 … ${dir.length > 40 ? '…${dir.substring(dir.length - 40)}' : dir}';
            // 初めてのときは、見つけた作品から順に見せる（2 秒ごと）
            final now = DateTime.now().millisecondsSinceEpoch;
            if (firstTime && now - lastShown > 2000) {
              lastShown = now;
              titles = sc.found;
            }
            notifyListeners();
          },
          cancelled: () => _cancel);
      final found = await sc.scan(settings.videoRoots, prefix: settings.folderPrefix);
      skipped = List.of(sc.errors);
      if (!_cancel) {
        titles = found;
        scannedAt = DateTime.now().millisecondsSinceEpoch;
        await _saveCache();
        await _applyRenameLogs(src);
        status = '${titles.length} 作品';
        if (found.isEmpty && settings.folderPrefix.trim().isNotEmpty) {
          error = '「${settings.folderPrefix.trim()}」で始まるフォルダが ${settings.videoRoots.join('・')} にありません'
              '（設定の「読むフォルダの目印」）';
        } else if (skipped.isNotEmpty) {
          error = '${skipped.length} か所のフォルダが読めませんでした（ほかは読み込み済み。⟳ でもう一度）';
        }
      } else {
        if (firstTime) titles = sc.found;
        status = '中止しました';
      }
    } on OtpRequired catch (e) {
      needOtp = true;
      error = e.message;
    } catch (e) {
      error = '$e';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// 整理の記録（共有フォルダの _整理の記録/*.csv）を読んで、続きから・並び順の選択を新しい場所に付け替える。
  /// 記録はファイル名の順（日時）に当て、当てた記録の名前は覚えて二度当てない（元に戻した記録も同じ形で残る）
  Progress? progress;

  Future<void> _applyRenameLogs(MediaSource src) async {
    final pr = progress;
    if (pr == null) return;
    for (final root in settings.videoRoots) {
      List<Entry> logs;
      try {
        logs = (await src.list('$root/_整理の記録')).where((e) => !e.isDir && e.name.toLowerCase().endsWith('.csv')).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      } catch (_) {
        continue; // 記録が無い
      }
      for (final log in logs) {
        final key = log.path;
        if (settings.appliedRenameLogs.contains(key)) continue;
        try {
          final b = await src.read(log.path);
          if (b == null) continue;
          final moves = parseRenameLog(utf8.decode(b, allowMalformed: true));
          final n = await pr.remap(moves);
          settings.episodeOrder = {
            for (final e in settings.episodeOrder.entries) remapPath(e.key, moves): e.value,
          };
          settings.appliedRenameLogs = [...settings.appliedRenameLogs, key];
          await settings.save();
          if (n > 0) status = '$status（整理の記録から $n 件の続きを引き継ぎ）';
        } catch (e) {
          debugPrint('rename log ${log.path}: $e');
        }
      }
    }
  }

  /// 棚（最上位フォルダ）の並び。規則の順を先に、ほかは名前順
  List<String> get shelves {
    const order = ['映画', 'アニメ映画', 'ドラマ', 'アニメ', 'テレビ', 'ライブ', 'ホームビデオ'];
    final s = {for (final t in titles) t.shelf}.toList();
    s.sort((a, b) {
      final x = order.indexOf(a), y = order.indexOf(b);
      if (x >= 0 || y >= 0) return (x < 0 ? 99 : x).compareTo(y < 0 ? 99 : y);
      return a.compareTo(b);
    });
    return s;
  }

  List<Title> onShelf(String shelf) => titles.where((t) => t.shelf == shelf).toList();

  List<Title> get recentlyAdded {
    final l = titles.where((t) => t.added > 0).toList()..sort((a, b) => b.added.compareTo(a.added));
    return l.take(20).toList();
  }

  Title? byId(String id) => titles.where((t) => t.id == id).firstOrNull;

  /// ファイルのパスから作品を探す（続きから）
  Title? titleOfFile(String path) {
    for (final t in titles) {
      if (t.allFiles.any((f) => f.path == path)) return t;
    }
    return null;
  }

  List<Title> search(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    return titles.where((t) {
      return t.displayName.toLowerCase().contains(s) ||
          t.name.toLowerCase().contains(s) ||
          t.info.originalTitle.toLowerCase().contains(s) ||
          t.info.cast.any((c) => c.toLowerCase().contains(s)) ||
          t.info.directors.any((c) => c.toLowerCase().contains(s));
    }).toList();
  }

  /// 同じ出演者・監督・コレクションの作品（関連）
  List<Title> related(Title t) {
    final people = {...t.info.cast.take(8), ...t.info.directors};
    final out = <Title, int>{};
    for (final o in titles) {
      if (o.id == t.id) continue;
      var score = 0;
      if (t.info.collection.isNotEmpty && o.info.collection == t.info.collection) score += 10;
      for (final p in [...o.info.cast.take(8), ...o.info.directors]) {
        if (people.contains(p)) score += 2;
      }
      if (score > 0) out[o] = score;
    }
    final l = out.keys.toList()..sort((a, b) => out[b]!.compareTo(out[a]!));
    return l.take(20).toList();
  }
}
