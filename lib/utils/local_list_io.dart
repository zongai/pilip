import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/storage_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 本地数据 JSON 导入导出（关注 / 黑名单 / 播单 / 历史 / 稍后再看）
abstract final class LocalListIo {
  static const followType = 'pilip_local_follows';
  static const playlistType = 'pilip_local_playlists';
  static const blacklistType = 'pilip_local_blacklist';
  static const historyType = 'pilip_local_history';
  static const laterType = 'pilip_local_later';

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
      allowedExtensions: const ['json'],
    );
  }

  /// 返回解析出的 items；失败返回 null。items 可为 Map 或数字（黑名单 mid）
  static Future<List?> import({required String expectedType}) async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (result == null) {
        SmartDialog.showToast('已取消');
        return null;
      }
      final String data = await result.xFile.readAsString();
      final dynamic decoded = jsonDecode(data);
      List rawItems;
      if (decoded is Map) {
        final t = decoded['type'];
        if (t != null && t != expectedType) {
          SmartDialog.showToast('文件类型不匹配（期望 $expectedType）');
          return null;
        }
        final items = decoded['items'] ?? decoded['mids'] ?? decoded['data'];
        if (items is! List) {
          SmartDialog.showToast('无效的备份文件');
          return null;
        }
        rawItems = items;
      } else if (decoded is List) {
        rawItems = decoded;
      } else {
        SmartDialog.showToast('无效的备份文件');
        return null;
      }
      return rawItems;
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

  // ---------- 关注 ----------
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

  // ---------- 黑名单 ----------
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
        final m = e['mid'] ?? e['id'];
        final id = m is int ? m : int.tryParse('$m');
        if (id != null && id != 0) mids.add(id);
      } else {
        final id = int.tryParse('$e');
        if (id != null && id != 0) mids.add(id);
      }
    }
    if (replace) {
      Pref.replaceBlackMids(mids);
      SmartDialog.showToast('已覆盖导入 ${mids.length} 个黑名单');
    } else {
      Pref.mergeBlackMids(mids);
      SmartDialog.showToast('已合并导入 ${mids.length} 个黑名单');
    }
  }

  // ---------- 播放列表 ----------
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
      SmartDialog.showToast('已覆盖导入 ${items.length} 个播放列表');
    } else {
      Pref.mergeLocalPlaylists(items);
      SmartDialog.showToast('已合并导入 ${items.length} 个播放列表');
    }
  }

  // ---------- 历史 ----------
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

  // ---------- 稍后再看 ----------
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
}
