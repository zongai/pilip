import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/video/source_type.dart';
import 'package:PiliPlus/models_new/media_list/media_list.dart';
import 'package:PiliPlus/models_new/media_list/page.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地视频播放列表：按标题排序，支持连续播放
class LocalVideoPlaylistPage extends StatefulWidget {
  const LocalVideoPlaylistPage({super.key});

  @override
  State<LocalVideoPlaylistPage> createState() => _LocalVideoPlaylistPageState();
}

class _LocalVideoPlaylistPageState extends State<LocalVideoPlaylistPage> {
  late List<Map> _list;
  final Set<String> _selected = {};
  bool _multi = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _list = List<Map>.from(GlobalData().localVideoPlaylistList);
      // 已按标题排序存储
    });
  }

  String _key(Map item) => item['bvid'] as String? ?? 'av${item['aid']}';

  List<MediaListItemModel> _toMediaList() {
    return _list.map((e) {
      final cid = e['cid'] as int?;
      return MediaListItemModel(
        aid: e['aid'] as int?,
        bvid: e['bvid'] as String?,
        title: e['title'] as String?,
        cover: e['cover'] as String?,
        duration: e['duration'] as int?,
        cid: cid,
        type: 2,
        pages: cid != null ? [Page(id: cid)] : null,
      );
    }).toList();
  }

  Future<void> _playFrom(int index) async {
    if (_list.isEmpty) return;
    final item = _list[index];
    final bvid = item['bvid'] as String?;
    int? aid = item['aid'] as int?;
    int? cid = item['cid'] as int?;
    if (cid == null || cid == 0) {
      cid = await SearchHttp.ab2c(aid: aid, bvid: bvid);
    }
    if (cid == null) {
      SmartDialog.showToast('无法打开视频');
      return;
    }
    if (aid == null && bvid != null) {
      try {
        aid = IdUtils.bv2av(bvid);
      } catch (_) {}
    }
    final mediaList = _toMediaList();
    // 补全当前项 cid
    if (index < mediaList.length) {
      mediaList[index]
        ..cid = cid
        ..pages = [Page(id: cid)];
    }
    PageUtils.toVideoPage(
      bvid: bvid,
      aid: aid,
      cid: cid,
      cover: item['cover'] as String?,
      title: item['title'] as String?,
      extraArguments: {
        'sourceType': SourceType.watchLater,
        'favTitle': '本地播放列表',
        'desc': true,
        'count': mediaList.length,
        'localMediaList': mediaList,
        'oid': aid,
      },
    );
  }

  void _remove(Map item) {
    Pref.removeLocalVideoPlaylistItem(
      aid: item['aid'] as int?,
      bvid: item['bvid'] as String?,
    );
    _selected.remove(_key(item));
    SmartDialog.showToast('已移除');
    _refresh();
  }

  void _removeSelected() {
    for (final k in _selected.toList()) {
      Map? item;
      for (final e in _list) {
        if (_key(e) == k) {
          item = e;
          break;
        }
      }
      if (item != null) {
        Pref.removeLocalVideoPlaylistItem(
          aid: item['aid'] as int?,
          bvid: item['bvid'] as String?,
        );
      }
    }
    _selected.clear();
    _multi = false;
    SmartDialog.showToast('已移除所选');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _multi
              ? '已选 ${_selected.length}'
              : '本地播放列表${_list.isEmpty ? '' : ' · ${_list.length}'}',
        ),
        actions: [
          if (_multi) ...[
            TextButton(
              onPressed: _selected.isEmpty ? null : _removeSelected,
              child: const Text('删除'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _multi = false;
                _selected.clear();
              }),
              child: const Text('取消'),
            ),
          ] else ...[
            if (_list.isNotEmpty)
              IconButton(
                tooltip: '多选',
                icon: const Icon(Icons.checklist),
                onPressed: () => setState(() => _multi = true),
              ),
            if (_list.isNotEmpty)
              TextButton(
                onPressed: () => _playFrom(0),
                child: const Text('连续播放'),
              ),
            if (_list.isNotEmpty)
              TextButton(
                onPressed: () {
                  Pref.clearLocalVideoPlaylist();
                  SmartDialog.showToast('已清空');
                  _refresh();
                },
                child: const Text('清空'),
              ),
          ],
        ],
      ),
      body: _list.isEmpty
          ? Center(
              child: Text(
                '播放列表为空\n在视频卡片菜单中「加入本地播放列表」\n列表按标题自动排序，可连续播放',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _list.length,
              itemBuilder: (context, index) {
                final item = _list[index];
                final title = item['title'] as String? ?? '';
                final cover = item['cover'] as String?;
                final author = item['authorName'] as String? ?? '';
                final duration = item['duration'] as int? ?? 0;
                final k = _key(item);
                final selected = _selected.contains(k);
                return ListTile(
                  selected: selected,
                  leading: _multi
                      ? Checkbox(
                          value: selected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(k);
                              } else {
                                _selected.remove(k);
                              }
                            });
                          },
                        )
                      : NetworkImgLayer(width: 96, height: 54, src: cover),
                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      if (author.isNotEmpty) author,
                      if (duration > 0)
                        DurationUtils.formatDuration(duration),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    if (_multi) {
                      setState(() {
                        if (selected) {
                          _selected.remove(k);
                        } else {
                          _selected.add(k);
                        }
                      });
                    } else {
                      _playFrom(index);
                    }
                  },
                  onLongPress: () {
                    if (!_multi) {
                      setState(() {
                        _multi = true;
                        _selected.add(k);
                      });
                    }
                  },
                  trailing: _multi
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => _remove(item),
                        ),
                );
              },
            ),
    );
  }
}
