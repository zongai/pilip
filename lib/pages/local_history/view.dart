import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地观看历史（无需登录）— 支持手动标注已看/未看
class LocalHistoryPage extends StatefulWidget {
  const LocalHistoryPage({super.key});

  @override
  State<LocalHistoryPage> createState() => _LocalHistoryPageState();
}

class _LocalHistoryPageState extends State<LocalHistoryPage> {
  final ScrollController _scrollController = ScrollController();

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
    final progress = item['progress'] as int? ?? 0;
    PageUtils.toVideoPage(
      bvid: bvid,
      aid: aid,
      cid: cid,
      cover: item['cover'] as String?,
      title: item['title'] as String?,
      progress: progress < 0 ? 0 : progress * 1000,
    );
  }

  void _remove(Map item) {
    final key = item['bvid'] as String? ?? 'av${item['aid']}';
    Pref.removeLocalHistory(key);
    SmartDialog.showToast('已删除');
    _refresh();
  }

  void _markCompleted(Map item) {
    Pref.markLocalWatched(
      aid: item['aid'] as int?,
      bvid: item['bvid'] as String?,
      cid: item['cid'] as int?,
      title: item['title'] as String?,
      cover: item['cover'] as String?,
      authorName: item['authorName'] as String?,
      authorMid: item['authorMid'] as int?,
      duration: item['duration'] as int?,
      completed: true,
    );
    SmartDialog.showToast('已标为已看完');
    _refresh();
  }

  void _markUnwatched(Map item) {
    Pref.markLocalUnwatched(
      aid: item['aid'] as int?,
      bvid: item['bvid'] as String?,
    );
    SmartDialog.showToast('已标为未看');
    _refresh();
  }

  void _showManageSheet(Map item) {
    final progress = item['progress'];
    final int prog = progress is int
        ? progress
        : (progress is num ? progress.toInt() : int.tryParse('$progress') ?? 0);
    final isCompleted = prog < 0;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  item['title'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('观看记录管理'),
              ),
              const Divider(height: 1),
              if (!isCompleted)
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('标为已看完'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _markCompleted(item);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('标为未看（从记录移除）'),
                onTap: () {
                  Navigator.pop(ctx);
                  _markUnwatched(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除'),
                onTap: () {
                  Navigator.pop(ctx);
                  _remove(item);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _statusLabel(Map item) {
    final progress = item['progress'];
    final int prog = progress is int
        ? progress
        : (progress is num ? progress.toInt() : int.tryParse('$progress') ?? 0);
    final duration = item['duration'] is int
        ? item['duration'] as int
        : int.tryParse('${item['duration']}') ?? 0;
    if (prog < 0) return '已看完';
    if (duration > 0 && prog >= (duration * 0.95).floor()) return '已看完';
    if (prog > 0 && duration > 0) {
      return '${DurationUtils.formatDuration(prog)} / ${DurationUtils.formatDuration(duration)}';
    }
    if (prog == 0) return '已看';
    return '';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrimaryScrollController(
      controller: _scrollController,
      child: Scaffold(
        appBar: AppBar(
          title: Text('观看记录${_list.isEmpty ? '' : ' · ${_list.length}'}'),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回',
            onPressed: () {
              final nav = Navigator.of(context);
              if (nav.canPop()) {
                nav.pop();
              } else if (Get.key.currentState?.canPop() == true) {
                Get.back();
              } else {
                Get.until((route) => route.isFirst);
              }
            },
          ),
          actions: [
            if (_list.isNotEmpty)
              TextButton(
                onPressed: () {
                  Pref.clearLocalHistory();
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
                  '暂无本地观看记录\n播放视频后会自动记录\n长按可标注已看/未看',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                itemCount: _list.length,
                itemBuilder: (context, index) {
                  final item = _list[index];
                  final title = item['title'] as String? ?? '';
                  final cover = item['cover'] as String?;
                  final author = item['authorName'] as String? ?? '';
                  final status = _statusLabel(item);
                  return ListTile(
                    leading: NetworkImgLayer(width: 96, height: 54, src: cover),
                    title: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (author.isNotEmpty) author,
                        if (status.isNotEmpty) status,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _open(item),
                    onLongPress: () => _showManageSheet(item),
                    onSecondaryTap: PlatformUtils.isMobile
                        ? null
                        : () => _showManageSheet(item),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert, size: 20),
                      tooltip: '管理',
                      onPressed: () => _showManageSheet(item),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
