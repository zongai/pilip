import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 本地关注 / 播放列表 JSON 导入导出
abstract final class LocalListIo {
  static const followType = 'pilip_local_follows';
  static const playlistType = 'pilip_local_playlists';

  static Future<void> export({
    required String type,
    required String fileName,
    required List<Map> items,
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

  /// 返回解析出的 items；失败返回 null
  static Future<List<Map>?> import({required String expectedType}) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        SmartDialog.showToast('已取消');
        return null;
      }
      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        SmartDialog.showToast('无法读取文件');
        return null;
      }
      final dynamic decoded = jsonDecode(utf8.decode(bytes));
      List rawItems;
      if (decoded is Map) {
        final t = decoded['type'];
        if (t != null && t != expectedType) {
          SmartDialog.showToast('文件类型不匹配（期望 $expectedType）');
          return null;
        }
        final items = decoded['items'];
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
      return rawItems
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      SmartDialog.showToast('导入失败: $e');
      return null;
    }
  }
}
