import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地稍后再看（无需登录）
class LocalLaterPage extends StatefulWidget {
  const LocalLaterPage({super.key});

  @override
  State<LocalLaterPage> createState() => _LocalLaterPageState();
}

class _LocalLaterPageState extends State<LocalLaterPage> {
  late List<Map> _list;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _list = List<Map>.from(GlobalData().localLaterList);
    });
  }

  Future<void> _open(Map item) async {
    final bvid = item['bvid'] as String?;
    final aid = item['aid'] as int?;
    int? cid = item['cid'] as int?;
    if (cid == null || cid == 0) {
      cid = await SearchHttp.ab2c(aid: aid, bvid: bvid);
    }
    if (cid == null) {
      SmartDialog.showToast('无法打开视频');
      return;
    }
    PageUtils.toVideoPage(
      bvid: bvid,
      aid: aid,
      cid: cid,
      cover: item['cover'] as String?,
      title: item['title'] as String?,
      progress: ((item['progress'] as int?) ?? 0) * 1000,
    );
  }

  void _remove(Map item) {
    Pref.removeLocalLater(
      aid: item['aid'] as int?,
      bvid: item['bvid'] as String?,
    );
    SmartDialog.showToast('已移除');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('本地稍后再看${_list.isEmpty ? '' : ' · ${_list.length}'}'),
        actions: [
          if (_list.isNotEmpty)
            TextButton(
              onPressed: () {
                Pref.clearLocalLater();
                SmartDialog.showToast('已清空');
                _refresh();
              },
              child: const Text('清空'),
            ),
        ],
      ),
      body: _list.isEmpty
          ? Center(
              child: Text(
                '暂无稍后再看\n在视频菜单中添加即可（无需登录）',
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
                return ListTile(
                  leading: NetworkImgLayer(width: 96, height: 54, src: cover),
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
                  onTap: () => _open(item),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => _remove(item),
                  ),
                );
              },
            ),
    );
  }
}
