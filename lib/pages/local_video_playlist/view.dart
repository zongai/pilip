import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
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

/// 本地播放列表管理（支持多个列表）
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
    // 使用 Navigator 避免在底栏嵌套场景下 Get.to 灰屏
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.playlist_add),
        label: const Text('新建'),
      ),
      body: _playlists.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music, size: 64, color: cs.outline),
                  const SizedBox(height: 12),
                  Text('还没有播放列表', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '点击下方按钮新建，或在视频菜单中加入',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: _playlists.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final pl = _playlists[index];
                final rawItems = pl['items'];
                final items = rawItems is List ? rawItems : const [];
                final title = pl['title'] as String? ?? '未命名';
                String? cover;
                if (items.isNotEmpty && items.first is Map) {
                  cover = (items.first as Map)['cover'] as String?;
                }
                final id = _asInt(pl['id']);
                return Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _open(pl),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: NetworkImgLayer(
                              width: 88,
                              height: 55,
                              src: cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${items.length} 个视频 · 按标题排序',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (items.isNotEmpty)
                            IconButton(
                              tooltip: '连续播放',
                              icon: Icon(Icons.play_circle_fill, color: cs.primary, size: 32),
                              onPressed: () async {
                                if (id == null) return;
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => LocalVideoPlaylistDetailPage(
                                      playlistId: id,
                                      title: title,
                                      autoPlay: true,
                                    ),
                                  ),
                                );
                                if (mounted) _refresh();
                              },
                            ),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (id == null) return;
                              if (v == 'rename') {
                                final ctrl = TextEditingController(text: title);
                                final name = await showDialog<String>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('重命名'),
                                    content: TextField(
                                      controller: ctrl,
                                      autofocus: true,
                                      decoration: const InputDecoration(
                                        hintText: '列表名称',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, ctrl.text.trim()),
                                        child: const Text('确定'),
                                      ),
                                    ],
                                  ),
                                );
                                if (name != null && name.isNotEmpty) {
                                  Pref.renameLocalVideoPlaylist(id, name);
                                  _refresh();
                                }
                              } else if (v == 'delete') {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('删除播放列表'),
                                    content: Text('确定删除「$title」？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  Pref.deleteLocalVideoPlaylist(id);
                                  SmartDialog.showToast('已删除');
                                  _refresh();
                                }
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'rename', child: Text('重命名')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// 单个播放列表详情
class LocalVideoPlaylistDetailPage extends StatefulWidget {
  const LocalVideoPlaylistDetailPage({
    super.key,
    required this.playlistId,
    required this.title,
    this.autoPlay = false,
  });

  final int playlistId;
  final String title;
  final bool autoPlay;

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
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _list.isNotEmpty) _playFrom(0);
      });
    }
  }

  void _refresh() {
    try {
      final items = Pref.getLocalVideoPlaylistItems(widget.playlistId);
      items.sort((a, b) => Pref.natCompareTitle(
            '${a['title'] ?? ''}',
            '${b['title'] ?? ''}',
          ));
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
    // 保证传给播放页的顺序为自然排序
    final sorted = List<Map>.from(_list);
    sorted.sort((a, b) => Pref.natCompareTitle(
          '${a['title'] ?? ''}',
          '${b['title'] ?? ''}',
        ));
    return sorted
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
    // 写入 GlobalData + Pref 持久化 playlistId（侧栏只从 Pref 读）
    final gd = GlobalData();
    gd.pendingLocalMediaList = maps;
    gd.pendingLocalMediaTitle = widget.title;
    gd.pendingLocalPlaylistId = widget.playlistId;
    gd.sessionLocalMediaList = maps;
    gd.sessionLocalMediaTitle = widget.title;
    gd.sessionLocalPlaylistId = widget.playlistId;
    Pref.lastLocalPlaylistId = widget.playlistId;
    Pref.lastLocalPlaylistTitle = widget.title;
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
        'localPlaylistId': widget.playlistId,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
              child: Text(
                '删除',
                style: TextStyle(color: _selected.isEmpty ? null : cs.error),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _multi = false;
                _selected.clear();
              }),
              child: const Text('完成'),
            ),
          ] else ...[
            IconButton(
              tooltip: '从历史加入',
              icon: const Icon(Icons.history),
              onPressed: _addFromHistory,
            ),
            if (_list.isNotEmpty)
              IconButton(
                tooltip: '多选',
                icon: const Icon(Icons.checklist_rtl),
                onPressed: () => setState(() => _multi = true),
              ),
          ],
        ],
      ),
      body: _error != null
          ? Center(child: Text('加载失败\n$_error', textAlign: TextAlign.center))
          : _list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.video_library_outlined,
                        size: 64, color: cs.outline),
                    const SizedBox(height: 16),
                    Text('列表还是空的', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '在视频页点「⋯」加入本地播单\n或点右上角从观看历史多选加入',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: cs.outline),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.tonalIcon(
                      onPressed: _addFromHistory,
                      icon: const Icon(Icons.history),
                      label: const Text('从历史加入'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _list.length,
                    itemBuilder: (context, index) {
                      final item = _list[index];
                      final title = item['title'] as String? ?? '';
                      final cover = item['cover'] as String?;
                      final author = item['authorName'] as String? ?? '';
                      final duration = _asInt(item['duration']) ?? 0;
                      final k = _key(item);
                      final selected = _selected.contains(k);
                      return InkWell(
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_multi)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: 4, top: 16),
                                  child: Checkbox(
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
                                  ),
                                )
                              else
                                SizedBox(
                                  width: 28,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 22),
                                    child: Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: cs.outline),
                                    ),
                                  ),
                                ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Stack(
                                  children: [
                                    NetworkImgLayer(
                                      width: 120,
                                      height: 68,
                                      src: cover,
                                    ),
                                    if (duration > 0)
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            DurationUtils.formatDuration(
                                                duration),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 68,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        title.isEmpty ? '无标题' : title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (author.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(color: cs.outline),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              if (!_multi)
                                IconButton(
                                  tooltip: '移除',
                                  icon: Icon(Icons.close,
                                      size: 18, color: cs.outline),
                                  onPressed: () {
                                    Pref.removeLocalVideoPlaylistItem(
                                      playlistId: widget.playlistId,
                                      aid: _asInt(item['aid']),
                                      bvid: item['bvid'] as String?,
                                    );
                                    _refresh();
                                  },
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!_multi && _list.isNotEmpty)
                  SafeArea(
                    top: false,
                    child: Material(
                      elevation: 6,
                      color: cs.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '共 ${_list.length} 个 · 按标题自然排序',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: cs.outline),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: () => _playFrom(0),
                              icon: const Icon(Icons.play_arrow, size: 20),
                              label: const Text('连续播放'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
