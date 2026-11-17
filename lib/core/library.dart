import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dsm.dart';
import 'models.dart';
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
      if (j['root'] != settings.videoRoot) return;
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
      'root': settings.videoRoot,
      'at': scannedAt,
      'titles': [for (final t in titles) t.toJson()],
    }));
  }

  bool _cancel = false;
  void cancel() => _cancel = true;

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    error = null;
    needOtp = false;
    _cancel = false;
    status = 'NAS につないでいます…';
    notifyListeners();
    try {
      final src = source;
      await src.check();
      final sc = Scanner(src.list, src.read,
          onProgress: (dir, n) {
            status = '$n 作品 … ${dir.length > 40 ? '…${dir.substring(dir.length - 40)}' : dir}';
            notifyListeners();
          },
          cancelled: () => _cancel);
      final found = await sc.scan(settings.videoRoot);
      if (!_cancel) {
        titles = found;
        scannedAt = DateTime.now().millisecondsSinceEpoch;
        await _saveCache();
        status = '${titles.length} 作品';
      } else {
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
