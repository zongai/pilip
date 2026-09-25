import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地观看历史（无需登录）
class LocalHistoryPage extends StatefulWidget {
  const LocalHistoryPage({super.key});

  @override
  State<LocalHistoryPage> createState() => _LocalHistoryPageState();
}

class _LocalHistoryPageState extends State<LocalHistoryPage> {
  late List<Map> _list;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _list = List<Map>.from(GlobalData().localHistoryList);
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
    final key = item['bvid'] as String? ?? 'av${item['aid']}';
    Pref.removeLocalHistory(key);
    SmartDialog.showToast('已删除');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('本地历史${_list.isEmpty ? '' : ' · ${_list.length}'}'),
        actions: [
          if (_list.isNotEmpty)
            TextButton(
              onPressed: () {
                Pref.clearLocalHistory();
                SmartDialog.showToast('已清空历史');
                _refresh();
              },
              child: const Text('清空'),
            ),
        ],
      ),
      body: _list.isEmpty
          ? Center(
              child: Text(
                '暂无本地观看记录\n播放视频后会自动记录',
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
                final progress = item['progress'] as int? ?? 0;
                final duration = item['duration'] as int? ?? 0;
                String? sub;
                if (duration > 0) {
                  final p = progress.clamp(0, duration);
                  sub = '${DurationUtils.formatDuration(p)} / ${DurationUtils.formatDuration(duration)}';
                }
                return ListTile(
                  leading: NetworkImgLayer(width: 96, height: 54, src: cover),
                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [if (author.isNotEmpty) author, if (sub != null) sub]
                        .join(' · '),
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
