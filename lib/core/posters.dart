import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'source.dart';

/// ポスター・背景の画像を NAS から取って端末に置いておく（キャッシュ。消しても取り直せる）
class Posters {
  final MediaSource Function() source;
  Posters(this.source);

  Directory? _dir;
  final _mem = <String, Uint8List?>{};
  final _pending = <String, Future<Uint8List?>>{};

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final d = Directory('${(await getApplicationCacheDirectory()).path}/posters');
    await d.create(recursive: true);
    return _dir = d;
  }

  Uint8List? cached(String path) => _mem[path];

  Future<Uint8List?> get(String path) {
    if (_mem.containsKey(path)) return Future.value(_mem[path]);
    return _pending[path] ??= _load(path).whenComplete(() => _pending.remove(path));
  }

  Future<Uint8List?> _load(String path) async {
    final f = File('${(await _cacheDir()).path}/${md5.convert(utf8.encode(path))}.img');
    try {
      if (await f.exists()) return _keep(path, await f.readAsBytes());
      final b = await source().read(path);
      if (b != null && b.isNotEmpty) await f.writeAsBytes(b);
      return _keep(path, b);
    } catch (_) {
      return null; // つながらないときは次に開いたときにもう一度
    }
  }

  Uint8List? _keep(String path, Uint8List? b) {
    if (_mem.length > 200) _mem.remove(_mem.keys.first);
    _mem[path] = b;
    return b;
  }

  Future<void> clear() async {
    _mem.clear();
    final d = await _cacheDir();
    if (await d.exists()) await d.delete(recursive: true);
    _dir = null;
  }
}
