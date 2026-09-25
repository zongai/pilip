import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地关注列表（无需登录）
class LocalFollowPage extends StatefulWidget {
  const LocalFollowPage({super.key});

  @override
  State<LocalFollowPage> createState() => _LocalFollowPageState();
}

class _LocalFollowPageState extends State<LocalFollowPage> {
  late List<Map> _list;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _list = List<Map>.from(GlobalData().localFollowList);
    });
  }

  void _unfollow(int mid, String name) {
    Pref.removeLocalFollow(mid);
    SmartDialog.showToast('已取消关注 $name');
    _refresh();
  }

  void _openVideos(Map item) {
    final mid = item['mid'];
    final name = (item['name'] as String?)?.trim();
    // 通过搜索获取该 UP 相关视频
    final keyword = (name != null && name.isNotEmpty) ? name : '$mid';
    Get.toNamed(
      '/searchResult',
      parameters: {'keyword': keyword},
      arguments: {'initIndex': 0},
    );
  }

  Future<void> _export() async {
    await LocalListIo.export(
      type: LocalListIo.followType,
      fileName: 'pilip_follows_${DateTime.now().millisecondsSinceEpoch}.json',
      items: _list,
    );
  }

  Future<void> _import({bool replace = false}) async {
    final items = await LocalListIo.import(expectedType: LocalListIo.followType);
    if (items == null) return;
    if (replace) {
      Pref.replaceLocalFollows(items);
      SmartDialog.showToast('已覆盖导入 ${items.length} 条关注');
    } else {
      Pref.mergeLocalFollows(items);
      SmartDialog.showToast('已合并导入 ${items.length} 条关注');
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('关注${_list.isEmpty ? '' : ' · ${_list.length}'}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '导入导出',
            onSelected: (v) {
              if (v == 'export') {
                _export();
              } else if (v == 'import_merge') {
                _import();
              } else if (v == 'import_replace') {
                _import(replace: true);
              }
            },
            itemBuilder: (context) => const [
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
                    Icons.person_add_alt_1_outlined,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text('暂无关注', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '在用户主页或视频页点击关注即可添加\n点击列表项将通过搜索查看其视频',
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
                final mid = item['mid'] as int? ?? 0;
                final name = (item['name'] as String?)?.isNotEmpty == true
                    ? item['name'] as String
                    : 'UID:$mid';
                final face = item['face'] as String?;
                return ListTile(
                  leading: NetworkImgLayer(
                    width: 48,
                    height: 48,
                    type: ImageType.avatar,
                    src: face,
                  ),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('UID: $mid'),
                  onTap: () => _openVideos(item),
                  onLongPress: () => Get.toNamed('/member?mid=$mid'),
                  trailing: IconButton(
                    tooltip: '取消关注',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => _unfollow(mid, name),
                  ),
                );
              },
            ),
    );
  }
}
