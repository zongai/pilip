import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地播放列表收藏：按宽度自适应列表 / 网格
class LocalPlaylistPage extends StatefulWidget {
  const LocalPlaylistPage({super.key});

  @override
  State<LocalPlaylistPage> createState() => _LocalPlaylistPageState();
}

class _LocalPlaylistPageState extends State<LocalPlaylistPage> {
  final ScrollController _scrollController = ScrollController();
  late List<Map> _list;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _list = List<Map>.from(GlobalData().localPlaylistList);
    });
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  void _remove(int mediaId, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('确定取消收藏「$title」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Pref.removeLocalPlaylist(mediaId);
              SmartDialog.showToast('已取消收藏「$title」');
              _refresh();
            },
            child: const Text('确定取消'),
          ),
        ],
      ),
    );
  }

  void _open(Map item) {
    final mediaId = _asInt(item['mediaId']);
    if (mediaId == null) return;
    final cover = item['cover'] as String? ?? '';
    Get.toNamed(
      '/favDetail',
      parameters: {
        'mediaId': '$mediaId',
        'heroTag': cover.isNotEmpty ? cover : Utils.makeHeroTag(mediaId),
      },
    );
  }

  Future<void> _export() async {
    await LocalListIo.exportPlaylists();
  }

  Future<void> _import({bool replace = false}) async {
    await LocalListIo.importPlaylists(replace: replace);
    _refresh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _tile(ThemeData theme, Map item, {required bool dense}) {
    final mediaId = _asInt(item['mediaId']) ?? 0;
    final title = (item['title'] as String?)?.isNotEmpty == true
        ? item['title'] as String
        : '播放列表 $mediaId';
    final cover = item['cover']?.toString();
    final count = _asInt(item['mediaCount']) ?? 0;
    final upper = item['upperName'] as String? ?? '';
    final coverW = dense ? 64.0 : 72.0;
    final coverH = dense ? 48.0 : 54.0;
    final sub = [
      if (upper.isNotEmpty) upper,
      if (count > 0) '$count 个视频',
    ].join(' · ');

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _open(item),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? Style.safeSpace : 8,
            vertical: 8,
          ),
          child: Row(
            children: [
              NetworkImgLayer(width: coverW, height: coverH, src: cover),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: '取消收藏',
                icon: const Icon(Icons.star),
                color: theme.colorScheme.primary,
                onPressed: () => _remove(mediaId, title),
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
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final hPad = MediaQuery.viewPaddingOf(context).horizontal;

    return PrimaryScrollController(
      controller: _scrollController,
      child: Scaffold(
        appBar: AppBar(
          title: Text('本地播单${_list.isEmpty ? '' : ' · ${_list.length}'}'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'export') {
                  _export();
                } else if (v == 'import_merge') {
                  _import();
                } else if (v == 'import_replace') {
                  _import(replace: true);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'export', child: Text('导出为 JSON')),
                PopupMenuItem(value: 'import_merge', child: Text('导入（合并）')),
                PopupMenuItem(value: 'import_replace', child: Text('导入（覆盖）')),
              ],
            ),
          ],
        ),
        body: _list.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.playlist_add_check,
                      size: 64,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text('暂无收藏的播放列表', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '在播放列表详情页点击「本地收藏」即可添加\n点击列表可直接进入该播放列表',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
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
                  final padH = maxW >= 600 ? 12.0 : 0.0;
                  final padding = EdgeInsets.only(
                    left: padH + hPad,
                    right: padH + hPad,
                    bottom: bottom + 24,
                  );

                  Widget child;
                  if (!useGrid) {
                    child = ListView.separated(
                      controller: _scrollController,
                      padding: padding,
                      itemCount: _list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _tile(theme, _list[index], dense: true),
                    );
                  } else {
                    child = GridView.builder(
                      controller: _scrollController,
                      padding: padding,
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxW >= 1100 ? 320.0 : 300.0,
                        mainAxisExtent: 72,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 10,
                      ),
                      itemCount: _list.length,
                      itemBuilder: (context, index) =>
                          _tile(theme, _list[index], dense: false),
                    );
                  }

                  if (maxW <= contentMax + 1) return child;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(width: contentMax, child: child),
                  );
                },
              ),
      ),
    );
  }
}
