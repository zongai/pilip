import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地合集收藏（无需登录）
class LocalSeasonPage extends StatefulWidget {
  const LocalSeasonPage({super.key});

  @override
  State<LocalSeasonPage> createState() => _LocalSeasonPageState();
}

class _LocalSeasonPageState extends State<LocalSeasonPage> {
  late List<Map> _list;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _list = List<Map>.from(GlobalData().localSeasonList);
    });
  }

  void _unfav(int id, String title) {
    Pref.removeLocalSeason(id);
    SmartDialog.showToast('已取消收藏 $title');
    _refresh();
  }

  void _openSeason(Map item) {
    final id = item['id'];
    if (id == null) return;
    // 进入合集详情（官方订阅详情页）
    Get.toNamed(
      '/subDetail',
      arguments: {
        'id': id,
        'heroTag': 'local_season_$id',
      },
      parameters: {
        'id': '$id',
        'type': '2', // 合集 type
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('合集收藏${_list.isEmpty ? '' : ' · ${_list.length}'}'),
      ),
      body: _list.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.video_library_outlined,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text('暂无合集收藏', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '在合集选集面板点击「订阅」即可添加\n加入后可在此管理，无需登录',
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
                final id = item['id'] as int? ?? 0;
                final title = (item['title'] as String?)?.isNotEmpty == true
                    ? item['title'] as String
                    : '合集 $id';
                final cover = item['cover'] as String?;
                final mediaCount = item['mediaCount'];
                final upperName = item['upperName'] as String?;
                final subtitle = [
                  if (upperName != null && upperName.isNotEmpty) upperName,
                  if (mediaCount != null && mediaCount != 0) '$mediaCount 个视频',
                  'ID: $id',
                ].join(' · ');
                return ListTile(
                  leading: NetworkImgLayer(
                    width: 64,
                    height: 40,
                    type: ImageType.video,
                    src: cover,
                  ),
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(subtitle),
                  onTap: () => _openSeason(item),
                  trailing: IconButton(
                    tooltip: '取消收藏',
                    icon: const Icon(Icons.notifications_off_outlined),
                    onPressed: () => _unfav(id, title),
                  ),
                );
              },
            ),
    );
  }
}
