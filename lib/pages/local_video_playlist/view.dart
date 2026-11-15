import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/local_watch_toggle.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/video/source_type.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

/// 本地播放列表管理（支持多个列表，随宽度自适应列数）
class LocalVideoPlaylistPage extends StatefulWidget {
  const LocalVideoPlaylistPage({super.key});

  @override
  State<LocalVideoPlaylistPage> createState() => _LocalVideoPlaylistPageState();
}

class _LocalVideoPlaylistPageState extends State<LocalVideoPlaylistPage> {
  late List<Map> _playlists;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _playlists = Pref.localVideoPlaylists
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (_playlists.isEmpty) {
        Pref.createLocalVideoPlaylist('默认列表');
        _playlists = Pref.localVideoPlaylists
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    });
  }

  Future<void> _create() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建播放列表'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '列表名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      Pref.createLocalVideoPlaylist(name);
      SmartDialog.showToast('已创建「$name」');
      _refresh();
    }
  }

  Future<void> _open(Map pl) async {
    final id = _asInt(pl['id']);
    if (id == null) {
      SmartDialog.showToast('列表数据异常');
      return;
    }
    final title = pl['title'] as String? ?? '播放列表';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalVideoPlaylistDetailPage(
          playlistId: id,
          title: title,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _rename(Map pl) async {
    final id = _asInt(pl['id']);
    if (id == null) return;
    final title = pl['title'] as String? ?? '';
    final ctrl = TextEditingController(text: title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      Pref.renameLocalVideoPlaylist(id, name);
      _refresh();
    }
  }

  void _delete(Map pl) {
    final id = _asInt(pl['id']);
    if (id == null) return;
    Pref.deleteLocalVideoPlaylist(id);
    SmartDialog.showToast('已删除');
    _refresh();
  }

  Widget _playlistTile(ThemeData theme, Map pl, {bool dense = true}) {
    final id = _asInt(pl['id']) ?? 0;
    final title = pl['name'] as String? ?? '列表';
    final items = Pref.getLocalVideoPlaylistItems(id);
    final cover = items.isNotEmpty ? items.first['cover'] as String? : null;
    final outline = theme.colorScheme.outline;
    final radius = dense ? BorderRadius.zero : BorderRadius.circular(12);
    final thumb = dense ? 64.0 : 56.0;

    return Material(
      color: dense
          ? null
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      type: dense ? MaterialType.transparency : MaterialType.canvas,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => _open(pl),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            dense ? Style.safeSpace : 12,
            dense ? 8 : 8,
            4,
            dense ? 8 : 8,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: NetworkImgLayer(
                  src: cover,
                  width: thumb,
                  height: thumb * 0.62,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${items.length} 个视频 · 按标题排序',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: outline),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'rename') {
                    _rename(pl);
                  } else if (v == 'delete') {
                    _delete(pl);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '本地播放列表${_playlists.isEmpty ? '' : ' · ${_playlists.length}'}',
        ),
        actions: [
          IconButton(
            tooltip: '新建列表',
            icon: const Icon(Icons.add),
            onPressed: _create,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _playlists.isEmpty
          ? Center(child: Text('暂无播放列表', style: TextStyle(color: outline)))
          : LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final useGrid = maxW >= 600;
                final contentMax = maxW >= 1400
                    ? 1200.0
                    : maxW >= 1000
                        ? 960.0
                        : maxW;
                final padH = maxW >= 600 ? 12.0 : 0.0;
                final padding = EdgeInsets.only(
                  left: padH,
                  right: padH,
                  top: 4,
                  bottom: 88,
                );

                Widget child;
                if (!useGrid) {
                  child = ListView.builder(
                    padding: padding,
                    itemCount: _playlists.length,
                    itemBuilder: (context, index) => _playlistTile(
                      theme,
                      _playlists[index],
                      dense: true,
                    ),
                  );
                } else {
                  child = GridView.builder(
                    padding: padding,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: maxW >= 1100 ? 300.0 : 280.0,
                      mainAxisExtent: 80,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: _playlists.length,
                    itemBuilder: (context, index) => _playlistTile(
                      theme,
                      _playlists[index],
                      dense: false,
                    ),
                  );
                }

                if (maxW <= contentMax + 1) return child;
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: contentMax, child: child),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('新建列表'),
      ),
    );
  }
}

/// 单个播放列表详情（随宽度自适应列数）
class LocalVideoPlaylistDetailPage extends StatefulWidget {
  const LocalVideoPlaylistDetailPage({
    super.key,
    required this.playlistId,
    required this.title,
  });

  final int playlistId;
  final String title;

  @override
  State<LocalVideoPlaylistDetailPage> createState() =>
      _LocalVideoPlaylistDetailPageState();
}

class _LocalVideoPlaylistDetailPageState
    extends State<LocalVideoPlaylistDetailPage> {
  List<Map> _list = [];
  final Set<String> _selected = {};
  bool _multi = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    try {
      final items = Pref.getLocalVideoPlaylistItems(widget.playlistId);
      setState(() {
        _list = items;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _list = [];
        _error = e.toString();
      });
    }
  }

  String _key(Map item) => item['bvid'] as String? ?? 'av${item['aid']}';

  List<Map> _toArgMaps() {
    return _list
        .map(
          (e) => {
            'aid': _asInt(e['aid']),
            'bvid': e['bvid'],
            'cid': _asInt(e['cid']),
            'title': e['title'],
            'cover': e['cover'],
            'duration': _asInt(e['duration']) ?? 0,
          },
        )
        .toList();
  }

  Future<void> _playFrom(int index) async {
    if (_list.isEmpty) return;
    final item = _list[index];
    final bvid = item['bvid'] as String?;
    int? aid = _asInt(item['aid']);
    int? cid = _asInt(item['cid']);
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
    final maps = _toArgMaps();
    if (index < maps.length) {
      maps[index]['cid'] = cid;
      maps[index]['aid'] = aid;
    }
    GlobalData().pendingLocalMediaList = maps;
    GlobalData().pendingLocalMediaTitle = widget.title;
    PageUtils.toVideoPage(
      bvid: bvid,
      aid: aid,
      cid: cid,
      cover: item['cover'] as String?,
      title: item['title'] as String?,
      extraArguments: {
        'sourceType': SourceType.watchLater,
        'favTitle': widget.title,
        'desc': true,
        'count': maps.length,
        'localMediaList': maps,
        'oid': aid,
      },
    );
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
          playlistId: widget.playlistId,
          aid: _asInt(item['aid']),
          bvid: item['bvid'] as String?,
        );
      }
    }
    _selected.clear();
    _multi = false;
    SmartDialog.showToast('已移除所选');
    _refresh();
  }

  Future<void> _addFromHistory() async {
    final history = List<Map>.from(Pref.localHistory);
    if (history.isEmpty) {
      SmartDialog.showToast('本地历史为空，请先观看视频');
      return;
    }
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(child: Text('从历史多选加入')),
                  TextButton(
                    onPressed: () {
                      setS(() {
                        if (selected.length == history.length) {
                          selected.clear();
                        } else {
                          for (final e in history) {
                            selected.add(
                              e['bvid'] as String? ?? 'av${e['aid']}',
                            );
                          }
                        }
                      });
                    },
                    child: Text(
                      selected.length == history.length ? '取消全选' : '全选',
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 360,
                child: ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (_, i) {
                    final e = history[i];
                    final k = e['bvid'] as String? ?? 'av${e['aid']}';
                    final checked = selected.contains(k);
                    return CheckboxListTile(
                      value: checked,
                      dense: true,
                      secondary: NetworkImgLayer(
                        width: 72,
                        height: 42,
                        src: e['cover'] as String?,
                      ),
                      title: Text(
                        e['title'] as String? ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: (v) {
                        setS(() {
                          if (v == true) {
                            selected.add(k);
                          } else {
                            selected.remove(k);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('加入 (${selected.length})'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true && selected.isNotEmpty) {
      final items = history
          .where((e) => selected.contains(e['bvid'] ?? 'av${e['aid']}'))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      Pref.addLocalVideoPlaylistItems(items, playlistId: widget.playlistId);
      SmartDialog.showToast('已加入 ${items.length} 个视频');
      _refresh();
    }
  }

  void _back() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      Get.back();
    }
  }

  Widget _videoTile(ThemeData theme, int index, Map item, {bool dense = true}) {
    final title = item['title'] as String? ?? '';
    final cover = item['cover'] as String?;
    final author = item['authorName'] as String? ?? '';
    final duration = _asInt(item['duration']) ?? 0;
    final aid = _asInt(item['aid']);
    final bvid = item['bvid'] as String?;
    final k = _key(item);
    final selected = _selected.contains(k);
    final outline = theme.colorScheme.outline;
    final watched = Pref.enableLocalFeatures &&
        Pref.isLocalWatched(aid: aid, bvid: bvid, duration: duration);
    return Material(
      type: MaterialType.transparency,
      color: selected
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.35)
          : null,
      child: InkWell(
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
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? Style.safeSpace : 8,
            vertical: 5,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_multi)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 28),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 22,
                    color: selected
                        ? theme.colorScheme.primary
                        : outline,
                  ),
                ),
              SizedBox(
                width: dense ? 140.0 : 120.0,
                child: AspectRatio(
                  aspectRatio: Style.aspectRatio,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      LocalWatchDim(
                        watched: watched,
                        child: NetworkImgLayer(
                          src: cover,
                          width: dense ? 140.0 : 120.0,
                          height: (dense ? 140.0 : 120.0) / Style.aspectRatio,
                        ),
                      ),
                      if (Pref.enableLocalFeatures)
                        LocalWatchProgressBar(
                          aid: aid,
                          bvid: bvid,
                          duration: duration,
                        ),
                      if (duration > 0)
                        PBadge(
                          text: DurationUtils.formatDuration(duration),
                          right: 6.0,
                          bottom: 6.0,
                          type: PBadgeType.gray,
                        ),
                      if (watched)
                        const PBadge(
                          text: '已看',
                          left: 6.0,
                          bottom: 6.0,
                          type: PBadgeType.gray,
                        ),
                      if (Pref.enableLocalFeatures && !_multi)
                        Positioned(
                          left: 2,
                          top: 2,
                          child: LocalWatchToggleIcon(
                            aid: aid,
                            bvid: bvid,
                            title: title,
                            cover: cover,
                            authorName: author,
                            duration: duration,
                            size: 20,
                            padding: const EdgeInsets.all(6),
                            onChanged: (_) {
                              if (mounted) setState(() {});
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 85,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? '无标题' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: theme.textTheme.bodyMedium!.fontSize,
                          height: 1.42,
                          letterSpacing: 0.3,
                          color: watched ? outline : null,
                        ),
                      ),
                      const Spacer(),
                      if (author.isNotEmpty)
                        Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: outline),
                        ),
                    ],
                  ),
                ),
              ),
              if (!_multi)
                IconButton(
                  tooltip: '移除',
                  icon: const Icon(Icons.close_outlined, size: 18),
                  onPressed: () {
                    Pref.removeLocalVideoPlaylistItem(
                      playlistId: widget.playlistId,
                      aid: aid,
                      bvid: bvid,
                    );
                    _refresh();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
        title: Text(
          _multi
              ? '已选 ${_selected.length}'
              : '${widget.title}${_list.isEmpty ? '' : ' · ${_list.length}'}',
        ),
        actions: [
          if (_multi) ...[
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selected.length == _list.length) {
                    _selected.clear();
                  } else {
                    for (final e in _list) {
                      _selected.add(_key(e));
                    }
                  }
                });
              },
              child: Text(_selected.length == _list.length ? '取消全选' : '全选'),
            ),
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
            IconButton(
              tooltip: '从历史多选加入',
              icon: const Icon(Icons.playlist_add),
              onPressed: _addFromHistory,
            ),
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
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: _error != null
          ? Center(
              child: Text('加载失败\n$_error', textAlign: TextAlign.center),
            )
          : _list.isEmpty
          ? Center(
              child: Text(
                '列表为空\n视频菜单可加入，或点右上角从历史多选加入',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: outline),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final useGrid = maxW >= 600;
                final contentMax = maxW >= 1400
                    ? 1200.0
                    : maxW >= 1000
                        ? 960.0
                        : maxW;
                final padH = maxW >= 600 ? 8.0 : 0.0;
                final padding = EdgeInsets.fromLTRB(padH, 4, padH, 24);

                Widget child;
                if (!useGrid) {
                  child = ListView.builder(
                    padding: padding,
                    itemCount: _list.length,
                    itemBuilder: (context, index) =>
                        _videoTile(theme, index, _list[index], dense: true),
                  );
                } else {
                  child = GridView.builder(
                    padding: padding,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: maxW >= 1100 ? 400.0 : 360.0,
                      mainAxisExtent: 96,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: _list.length,
                    itemBuilder: (context, index) =>
                        _videoTile(theme, index, _list[index], dense: false),
                  );
                }

                if (maxW <= contentMax + 1) return child;
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: contentMax, child: child),
                );
              },
            ),
    );
  }
}
