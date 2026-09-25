import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地播放列表收藏（无需登录）
class LocalPlaylistPage extends StatefulWidget {
  const LocalPlaylistPage({super.key});

  @override
  State<LocalPlaylistPage> createState() => _LocalPlaylistPageState();
}

class _LocalPlaylistPageState extends State<LocalPlaylistPage> {
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

  void _remove(int mediaId, String title) {
    Pref.removeLocalPlaylist(mediaId);
    SmartDialog.showToast('已取消收藏「$title」');
    _refresh();
  }

  /// 点击直接进入播放列表详情
  void _open(Map item) {
    final mediaId = item['mediaId'];
    final cover = item['cover'] as String? ?? '';
    Get.toNamed(
      '/favDetail',
      parameters: {
        'mediaId': '$mediaId',
        'heroTag': cover.isNotEmpty ? cover : Utils.makeHeroTag(mediaId),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '本地播放列表${_list.isEmpty ? '' : ' · ${_list.length}'}',
        ),
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
          : ListView.builder(
              itemCount: _list.length,
              itemBuilder: (context, index) {
                final item = _list[index];
                final mediaId = item['mediaId'] as int? ?? 0;
                final title = (item['title'] as String?)?.isNotEmpty == true
                    ? item['title'] as String
                    : '播放列表 $mediaId';
                final cover = item['cover'] as String?;
                final count = item['mediaCount'] as int? ?? 0;
                final upper = item['upperName'] as String? ?? '';
                return ListTile(
                  leading: NetworkImgLayer(
                    width: 64,
                    height: 48,
                    src: cover,
                  ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (upper.isNotEmpty) upper,
                      if (count > 0) '$count 个视频',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _open(item),
                  trailing: IconButton(
                    tooltip: '取消收藏',
                    icon: const Icon(Icons.star),
                    color: theme.colorScheme.primary,
                    onPressed: () => _remove(mediaId, title),
                  ),
                );
              },
            ),
    );
  }
}
