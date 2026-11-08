import 'dart:convert';
import 'package:archive/archive.dart';
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/storage_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 本地数据 JSON 导入导出（一次性打包全部）
abstract final class LocalListIo {
  static const followType = 'pilip_local_follows';
  static const playlistType = 'pilip_local_playlists';
  static const blacklistType = 'pilip_local_blacklist';
  static const historyType = 'pilip_local_history';
  static const laterType = 'pilip_local_later';
  static const allType = 'pilip_local_all';
  static const searchHistoryType = 'pilip_search_history';

  static const _searchCacheKey = 'cacheList';

  static List<String> get searchHistoryList {
    final raw = GStorage.historyWord.get(_searchCacheKey);
    if (raw is! List) return <String>[];
    return [for (final e in raw) if ('$e'.trim().isNotEmpty) '$e'];
  }

  static Future<void> export({
    required String type,
    required String fileName,
    required List items,
  }) async {
    final payload = {
      'type': type,
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'count': items.length,
      'items': items,
    };
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(json));
    await StorageUtils.saveBytes2File(
      name: fileName,
      bytes: bytes,
    );
  }

  static Future<void> exportPayload({
    required Map<String, dynamic> payload,
    required String fileName,
  }) async {
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(json));
    await StorageUtils.saveBytes2File(name: fileName, bytes: bytes);
  }

  /// 返回解析出的 items；失败返回 null
  static Future<List?> import({required String expectedType}) async {
    final decoded = await _pickJson();
    if (decoded == null) return null;
    if (decoded is Map) {
      final t = decoded['type'];
      if (t != null && t != expectedType && t != allType) {
        SmartDialog.showToast('文件类型不匹配（期望 $expectedType）');
        return null;
      }
      // 全部包里的单项
      if (t == allType && expectedType != allType) {
        final data = decoded['data'];
        if (data is! Map) {
          SmartDialog.showToast('无效的备份文件');
          return null;
        }
        final key = switch (expectedType) {
          followType => 'follows',
          blacklistType => 'blacklist',
          playlistType => 'playlists',
          historyType => 'history',
          laterType => 'later',
          searchHistoryType => 'searchHistory',
          _ => null,
        };
        if (key == null) return null;
        final items = data[key];
        if (items is! List) {
          SmartDialog.showToast('备份中无对应数据');
          return null;
        }
        return items;
      }
      final items = decoded['items'] ?? decoded['mids'] ?? decoded['data'];
      if (items is! List) {
        SmartDialog.showToast('无效的备份文件');
        return null;
      }
      return items;
    }
    if (decoded is List) return decoded;
    SmartDialog.showToast('无效的备份文件');
    return null;
  }

  static Future<dynamic> _pickJson() async {
    try {
      final result = await FilePicker.pickFile(
        type: .custom,
        allowedExtensions: const ['json'],
      );
      if (result == null) {
        SmartDialog.showToast('已取消');
        return null;
      }
      final String data = await result.xFile.readAsString();
      return jsonDecode(data);
    } catch (e) {
      SmartDialog.showToast('导入失败: $e');
      return null;
    }
  }

  static List<Map> _asMaps(List raw) {
    return raw
        .map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          if (e is int) return {'mid': e};
          if (e is num) return {'mid': e.toInt()};
          final n = int.tryParse('$e');
          if (n != null) return {'mid': n};
          return null;
        })
        .whereType<Map>()
        .toList();
  }

  static List<String> _asStrings(List raw) {
    return [
      for (final e in raw)
        if ('$e'.trim().isNotEmpty) '$e'.trim(),
    ];
  }

  // ---------- 全部（一次导出/导入）----------
  static Map<String, dynamic> _collectAll() {
    return {
      'follows': Pref.localFollows,
      'blacklist': Pref.blackMids.map((mid) => {'mid': mid}).toList(),
      'playlists': Pref.localPlaylists,
      'videoPlaylists': Pref.localVideoPlaylists,
      'seasons': Pref.localSeasons,
      'history': Pref.localHistory,
      'later': Pref.localLater,
      'searchHistory': searchHistoryList,
      'favHideKeywords': Pref.favHideKeywords,
    };
  }

  static Map<String, dynamic> buildFullPayload() {
    final data = _collectAll();
    final counts = {
      for (final e in data.entries)
        e.key: e.value is List ? (e.value as List).length : 0,
    };
    return {
      'type': allType,
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'counts': counts,
      'data': data,
    };
  }

  /// 单段二维码建议容量（字符）。过长手机难扫。
  static const int qrChunkSize = 800;

  static const String qrPrefix = 'P1S'; // PiliPlus Sync

  /// 将全部本地数据压缩并切分为二维码文本列表
  static List<String> buildQrChunks() {
    final payload = buildFullPayload();
    final jsonStr = jsonEncode(payload);
    final raw = utf8.encode(jsonStr);
    final gzipped = const GZipEncoder().encodeBytes(raw);
    final b64 = base64UrlEncode(gzipped).replaceAll('=', '');
    if (b64.length <= qrChunkSize) {
      return ['$qrPrefix|1|1|$b64'];
    }
    final chunks = <String>[];
    final total = (b64.length / qrChunkSize).ceil();
    for (var i = 0; i < total; i++) {
      final start = i * qrChunkSize;
      final end = (start + qrChunkSize).clamp(0, b64.length);
      chunks.add('$qrPrefix|${i + 1}|$total|${b64.substring(start, end)}');
    }
    return chunks;
  }

  /// 解析一段或多段二维码内容，合并后导入
  static Future<bool> importFromQrTexts(
    Iterable<String> texts, {
    bool replace = false,
  }) async {
    final parts = <int, String>{};
    int? total;
    for (final raw in texts) {
      final text = raw.trim();
      if (text.isEmpty) continue;
      if (!text.startsWith('$qrPrefix|')) {
        // 允许直接粘贴完整 JSON
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map) {
            await applyDecodedMap(decoded, replace: replace);
            return true;
          }
        } catch (_) {}
        continue;
      }
      final segs = text.split('|');
      if (segs.length < 4) continue;
      final idx = int.tryParse(segs[1]);
      final tot = int.tryParse(segs[2]);
      if (idx == null || tot == null || idx < 1 || tot < 1) continue;
      total ??= tot;
      final body = segs.sublist(3).join('|');
      parts[idx] = body;
    }
    if (parts.isEmpty) {
      SmartDialog.showToast('未识别到有效同步数据');
      return false;
    }
    final t = total ?? parts.length;
    if (parts.length < t) {
      SmartDialog.showToast('二维码不完整：${parts.length}/$t，请继续扫描或粘贴');
      return false;
    }
    final buf = StringBuffer();
    for (var i = 1; i <= t; i++) {
      final p = parts[i];
      if (p == null) {
        SmartDialog.showToast('缺少第 $i/$t 段');
        return false;
      }
      buf.write(p);
    }
    try {
      var b64 = buf.toString();
      final pad = (4 - b64.length % 4) % 4;
      b64 = b64.padRight(b64.length + pad, '=');
      final gzipped = base64Url.decode(b64);
      final raw = const GZipDecoder().decodeBytes(gzipped);
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map) {
        SmartDialog.showToast('同步数据无效');
        return false;
      }
      await applyDecodedMap(Map<String, dynamic>.from(decoded), replace: replace);
      return true;
    } catch (e) {
      SmartDialog.showToast('解析失败: $e');
      return false;
    }
  }

  static Future<void> applyDecodedMap(
    Map decoded, {
    required bool replace,
  }) async {
    Map? data;
    final t = decoded['type'];
    if (t == allType) {
      final d = decoded['data'];
      if (d is Map) data = d;
    } else if (decoded['data'] is Map) {
      data = decoded['data'] as Map;
    } else {
      await _importLegacySingle(decoded, replace: replace);
      return;
    }
    if (data == null) {
      SmartDialog.showToast('无效的备份数据');
      return;
    }
    await _applyAllData(data, replace: replace);
  }

  static Future<void> exportAll() async {
    final data = _collectAll();
    final counts = {
      for (final e in data.entries)
        e.key: e.value is List ? (e.value as List).length : 0,
    };
    await exportPayload(
      fileName: 'pilip_all_${DateTime.now().millisecondsSinceEpoch}.json',
      payload: {
        'type': allType,
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'counts': counts,
        'data': data,
      },
    );
  }

  static Future<void> importAll({bool replace = false}) async {
    final decoded = await _pickJson();
    if (decoded == null) return;

    Map? data;
    if (decoded is Map) {
      final t = decoded['type'];
      if (t == allType) {
        final d = decoded['data'];
        if (d is Map) {
          data = d;
        }
      } else if (decoded['data'] is Map) {
        data = decoded['data'] as Map;
      } else {
        // 兼容旧单类型文件：按 type 单项导入
        await _importLegacySingle(decoded, replace: replace);
        return;
      }
    }
    if (data == null) {
      SmartDialog.showToast('无效的全部备份文件');
      return;
    }
    await _applyAllData(data, replace: replace);
  }

  static Future<void> _applyAllData(Map data, {required bool replace}) async {
    final parts = <String>[];

    void applyMaps(
      String key,
      String label,
      void Function(List<Map>, {required bool replace}) apply,
    ) {
      final raw = data![key];
      if (raw is! List || raw.isEmpty) return;
      final items = _asMaps(raw);
      if (items.isEmpty) return;
      apply(items, replace: replace);
      parts.add('$label ${items.length}');
    }

    applyMaps('follows', '关注', (items, {required replace}) {
      if (replace) {
        Pref.replaceLocalFollows(items);
      } else {
        Pref.mergeLocalFollows(items);
      }
    });

    final bl = data['blacklist'];
    if (bl is List && bl.isNotEmpty) {
      final mids = <int>{};
      for (final e in bl) {
        if (e is int) {
          mids.add(e);
        } else if (e is num) {
          mids.add(e.toInt());
        } else if (e is Map) {
          final m = e['mid'];
          if (m is int) {
            mids.add(m);
          } else if (m is num) {
            mids.add(m.toInt());
          } else {
            final n = int.tryParse('$m');
            if (n != null) mids.add(n);
          }
        } else {
          final n = int.tryParse('$e');
          if (n != null) mids.add(n);
        }
      }
      if (mids.isNotEmpty) {
        if (replace) {
          Pref.blackMids = mids;
          GlobalData().blackMids = mids;
        } else {
          final next = {...Pref.blackMids, ...mids};
          Pref.blackMids = next;
          GlobalData().blackMids = next;
        }
        parts.add('黑名单 ${mids.length}');
      }
    }

    applyMaps('playlists', '播单', (items, {required replace}) {
      if (replace) {
        Pref.replaceLocalPlaylists(items);
      } else {
        Pref.mergeLocalPlaylists(items);
      }
    });

    // 本地视频播放列表
    final vpls = data['videoPlaylists'];
    if (vpls is List && vpls.isNotEmpty) {
      final items = _asMaps(vpls);
      if (items.isNotEmpty) {
        if (replace) {
          Pref.localVideoPlaylists = items;
        } else {
          final cur = List<Map>.from(Pref.localVideoPlaylists);
          final byId = <dynamic, Map>{
            for (final e in cur)
              if (e['id'] != null) e['id']: Map<String, dynamic>.from(e),
          };
          for (final e in items) {
            final id = e['id'];
            if (id != null && byId.containsKey(id)) {
              byId[id] = e;
            } else if (id != null) {
              byId[id] = e;
            } else {
              cur.add(e);
            }
          }
          Pref.localVideoPlaylists = [
            ...byId.values,
            ...cur.where((e) => e['id'] == null),
          ];
        }
        parts.add('视频播单 ${items.length}');
      }
    }

    final seasons = data['seasons'];
    if (seasons is List && seasons.isNotEmpty) {
      final items = _asMaps(seasons);
      if (items.isNotEmpty) {
        if (replace) {
          Pref.localSeasons = items;
          GlobalData().localSeasonList = items;
          GlobalData().localSeasonIds = {
            for (final e in items)
              if (e['id'] is int) e['id'] as int,
          };
        } else {
          final cur = List<Map>.from(Pref.localSeasons);
          final ids = {
            for (final e in cur)
              if (e['id'] != null) e['id'],
          };
          for (final e in items) {
            final id = e['id'];
            if (id != null && ids.contains(id)) {
              final i = cur.indexWhere((x) => x['id'] == id);
              if (i >= 0) cur[i] = e;
            } else {
              cur.add(e);
              if (id != null) ids.add(id);
            }
          }
          Pref.localSeasons = cur;
          GlobalData().localSeasonList = cur;
          GlobalData().localSeasonIds = {
            for (final e in cur)
              if (e['id'] is int) e['id'] as int,
          };
        }
        parts.add('合集 ${items.length}');
      }
    }

    applyMaps('history', '历史', (items, {required replace}) {
      if (replace) {
        Pref.replaceLocalHistory(items);
      } else {
        Pref.mergeLocalHistory(items);
      }
    });

    applyMaps('later', '稍后再看', (items, {required replace}) {
      if (replace) {
        Pref.replaceLocalLater(items);
      } else {
        Pref.mergeLocalLater(items);
      }
    });

    final sh = data['searchHistory'];
    if (sh is List && sh.isNotEmpty) {
      final words = _asStrings(sh);
      if (words.isNotEmpty) {
        if (replace) {
          GStorage.historyWord.put(_searchCacheKey, words);
        } else {
          final cur = searchHistoryList;
          final seen = cur.toSet();
          final merged = [...cur];
          for (final w in words) {
            if (seen.add(w)) merged.add(w);
          }
          GStorage.historyWord.put(_searchCacheKey, merged);
        }
        parts.add('搜索历史 ${words.length}');
      }
    }

    final kws = data['favHideKeywords'];
    if (kws is List && kws.isNotEmpty) {
      final words = _asStrings(kws);
      if (words.isNotEmpty) {
        if (replace) {
          Pref.favHideKeywords = words;
        } else {
          for (final w in words) {
            Pref.addFavHideKeyword(w);
          }
        }
        parts.add('隐藏关键字 ${words.length}');
      }
    }

    if (parts.isEmpty) {
      SmartDialog.showToast('备份中无可导入数据');
    } else {
      SmartDialog.showToast(
        '${replace ? '已覆盖' : '已合并'}导入：${parts.join(' · ')}',
      );
    }
  }

  static Future<void> _importLegacySingle(
    Map decoded, {
    required bool replace,
  }) async {
    final t = decoded['type'];
    final items = decoded['items'] ?? decoded['mids'] ?? decoded['data'];
    if (items is! List) {
      SmartDialog.showToast('无效的备份文件');
      return;
    }
    switch (t) {
      case followType:
        final maps = _asMaps(items);
        if (replace) {
          Pref.replaceLocalFollows(maps);
        } else {
          Pref.mergeLocalFollows(maps);
        }
        SmartDialog.showToast('已导入关注 ${maps.length}');
      case blacklistType:
        final mids = <int>{};
        for (final e in items) {
          if (e is int) {
            mids.add(e);
          } else if (e is num) {
            mids.add(e.toInt());
          } else if (e is Map) {
            final m = e['mid'];
            if (m is int) {
              mids.add(m);
            } else if (m is num) {
              mids.add(m.toInt());
            } else {
              final n = int.tryParse('$m');
              if (n != null) mids.add(n);
            }
          } else {
            final n = int.tryParse('$e');
            if (n != null) mids.add(n);
          }
        }
        if (replace) {
          Pref.blackMids = mids;
          GlobalData().blackMids = mids;
        } else {
          final next = {...Pref.blackMids, ...mids};
          Pref.blackMids = next;
          GlobalData().blackMids = next;
        }
        SmartDialog.showToast('已导入黑名单 ${mids.length}');
      case playlistType:
        final maps = _asMaps(items);
        if (replace) {
          Pref.replaceLocalPlaylists(maps);
        } else {
          Pref.mergeLocalPlaylists(maps);
        }
        SmartDialog.showToast('已导入播单 ${maps.length}');
      case historyType:
        final maps = _asMaps(items);
        if (replace) {
          Pref.replaceLocalHistory(maps);
        } else {
          Pref.mergeLocalHistory(maps);
        }
        SmartDialog.showToast('已导入历史 ${maps.length}');
      case laterType:
        final maps = _asMaps(items);
        if (replace) {
          Pref.replaceLocalLater(maps);
        } else {
          Pref.mergeLocalLater(maps);
        }
        SmartDialog.showToast('已导入稍后再看 ${maps.length}');
      case searchHistoryType:
        final words = _asStrings(items);
        if (replace) {
          GStorage.historyWord.put(_searchCacheKey, words);
        } else {
          final cur = searchHistoryList;
          final seen = cur.toSet();
          final merged = [...cur];
          for (final w in words) {
            if (seen.add(w)) merged.add(w);
          }
          GStorage.historyWord.put(_searchCacheKey, merged);
        }
        SmartDialog.showToast('已导入搜索历史 ${words.length}');
      default:
        SmartDialog.showToast('无法识别的备份类型');
    }
  }

  // ---------- 单项（兼容）----------
  static Future<void> exportFollows() => export(
        type: followType,
        fileName: 'pilip_follows_${DateTime.now().millisecondsSinceEpoch}.json',
        items: Pref.localFollows,
      );

  static Future<void> importFollows({bool replace = false}) async {
    final raw = await import(expectedType: followType);
    if (raw == null) return;
    final items = _asMaps(raw);
    if (replace) {
      Pref.replaceLocalFollows(items);
      SmartDialog.showToast('已覆盖导入 ${items.length} 条关注');
    } else {
      Pref.mergeLocalFollows(items);
      SmartDialog.showToast('已合并导入 ${items.length} 条关注');
    }
  }

  static Future<void> exportBlacklist() {
    final items = Pref.blackMids.map((mid) => {'mid': mid}).toList();
    return export(
      type: blacklistType,
      fileName: 'pilip_blacklist_${DateTime.now().millisecondsSinceEpoch}.json',
      items: items,
    );
  }

  static Future<void> importBlacklist({bool replace = false}) async {
    final raw = await import(expectedType: blacklistType);
    if (raw == null) return;
    final mids = <int>{};
    for (final e in raw) {
      if (e is int) {
        mids.add(e);
      } else if (e is num) {
        mids.add(e.toInt());
      } else if (e is Map) {
        final m = e['mid'];
        if (m is int) {
          mids.add(m);
        } else if (m is num) {
          mids.add(m.toInt());
        } else {
          final n = int.tryParse('$m');
          if (n != null) mids.add(n);
        }
      } else {
        final n = int.tryParse('$e');
        if (n != null) mids.add(n);
      }
    }
    if (replace) {
      Pref.blackMids = mids;
      GlobalData().blackMids = mids;
    } else {
      final next = {...Pref.blackMids, ...mids};
      Pref.blackMids = next;
      GlobalData().blackMids = next;
    }
    SmartDialog.showToast('${replace ? '覆盖' : '合并'}导入黑名单 ${mids.length}');
  }

  static Future<void> exportPlaylists() => export(
        type: playlistType,
        fileName:
            'pilip_playlists_${DateTime.now().millisecondsSinceEpoch}.json',
        items: Pref.localPlaylists,
      );

  static Future<void> importPlaylists({bool replace = false}) async {
    final raw = await import(expectedType: playlistType);
    if (raw == null) return;
    final items = _asMaps(raw);
    if (replace) {
      Pref.replaceLocalPlaylists(items);
      SmartDialog.showToast('已覆盖导入 ${items.length} 条播放列表');
    } else {
      Pref.mergeLocalPlaylists(items);
      SmartDialog.showToast('已合并导入 ${items.length} 条播放列表');
    }
  }

  static Future<void> exportHistory() => export(
        type: historyType,
        fileName: 'pilip_history_${DateTime.now().millisecondsSinceEpoch}.json',
        items: Pref.localHistory,
      );

  static Future<void> importHistory({bool replace = false}) async {
    final raw = await import(expectedType: historyType);
    if (raw == null) return;
    final items = _asMaps(raw);
    if (replace) {
      Pref.replaceLocalHistory(items);
      SmartDialog.showToast('已覆盖导入 ${items.length} 条历史');
    } else {
      Pref.mergeLocalHistory(items);
      SmartDialog.showToast('已合并导入 ${items.length} 条历史');
    }
  }

  static Future<void> exportLater() => export(
        type: laterType,
        fileName: 'pilip_later_${DateTime.now().millisecondsSinceEpoch}.json',
        items: Pref.localLater,
      );

  static Future<void> importLater({bool replace = false}) async {
    final raw = await import(expectedType: laterType);
    if (raw == null) return;
    final items = _asMaps(raw);
    if (replace) {
      Pref.replaceLocalLater(items);
      SmartDialog.showToast('已覆盖导入 ${items.length} 条稍后再看');
    } else {
      Pref.mergeLocalLater(items);
      SmartDialog.showToast('已合并导入 ${items.length} 条稍后再看');
    }
  }

  static Future<void> exportSearchHistory() => export(
        type: searchHistoryType,
        fileName:
            'pilip_search_history_${DateTime.now().millisecondsSinceEpoch}.json',
        items: searchHistoryList,
      );

  static Future<void> importSearchHistory({bool replace = false}) async {
    final raw = await import(expectedType: searchHistoryType);
    if (raw == null) return;
    final words = _asStrings(raw);
    if (replace) {
      GStorage.historyWord.put(_searchCacheKey, words);
    } else {
      final cur = searchHistoryList;
      final seen = cur.toSet();
      final merged = [...cur];
      for (final w in words) {
        if (seen.add(w)) merged.add(w);
      }
      GStorage.historyWord.put(_searchCacheKey, merged);
    }
    SmartDialog.showToast('${replace ? '覆盖' : '合并'}导入搜索历史 ${words.length}');
  }
}
