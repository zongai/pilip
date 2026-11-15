import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地关注列表：按窗口宽度在列表 / 网格间切换
class LocalFollowPage extends StatefulWidget {
  const LocalFollowPage({super.key});

  @override
  State<LocalFollowPage> createState() => _LocalFollowPageState();
}

class _LocalFollowPageState extends State<LocalFollowPage> {
  final ScrollController _scrollController = ScrollController();
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消关注'),
        content: Text('确定取消关注「$name」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Pref.removeLocalFollow(mid);
              SmartDialog.showToast('已取消关注 $name');
              _refresh();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _openMember(Map item) {
    final mid = item['mid'];
    if (mid == null) return;
    Get.toNamed('/member?mid=$mid');
  }

  Future<void> _export() async {
    await LocalListIo.exportFollows();
  }

  Future<void> _import({bool replace = false}) async {
    await LocalListIo.importFollows(replace: replace);
    _refresh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return PrimaryScrollController(
      controller: _scrollController,
      child: Scaffold(
        appBar: AppBar(
          title: Text('本地关注${_list.isEmpty ? '' : ' · ${_list.length}'}'),
          actions: [
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (v) {
                switch (v) {
                  case 'export':
                    _export();
                  case 'import_merge':
                    _import();
                  case 'import_replace':
                    _import(replace: true);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'export', child: Text('导出')),
                PopupMenuItem(value: 'import_merge', child: Text('导入（合并）')),
                PopupMenuItem(value: 'import_replace', child: Text('导入（覆盖）')),
              ],
            ),
          ],
        ),
        body: _list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
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
                        '在用户主页或视频页点击关注即可添加\n点击列表项进入该 UP 主页',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  // 手机单列；≥600 网格；大屏限制内容最大宽度
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
                    bottom: bottom + 24,
                  );

                  Widget child;
                  if (!useGrid) {
                    child = ListView.separated(
                      controller: _scrollController,
                      padding: padding,
                      itemCount: _list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => _FollowTile(
                        item: _list[index],
                        dense: true,
                        onOpen: _openMember,
                        onUnfollow: _unfollow,
                      ),
                    );
                  } else {
                    final crossExtent = maxW >= 1100 ? 300.0 : 280.0;
                    child = GridView.builder(
                      controller: _scrollController,
                      padding: padding,
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: crossExtent,
                        mainAxisExtent: 80,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 10,
                      ),
                      itemCount: _list.length,
                      itemBuilder: (context, index) => _FollowTile(
                        item: _list[index],
                        dense: false,
                        onOpen: _openMember,
                        onUnfollow: _unfollow,
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
      ),
    );
  }
}

class _FollowTile extends StatelessWidget {
  const _FollowTile({
    required this.item,
    required this.onOpen,
    required this.onUnfollow,
    this.dense = true,
  });

  final Map item;
  final void Function(Map item) onOpen;
  final void Function(int mid, String name) onUnfollow;
  final bool dense;

  static int _midOf(Map item) {
    final v = item['mid'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mid = _midOf(item);
    final name = (item['name'] as String?)?.isNotEmpty == true
        ? item['name'] as String
        : 'UID:$mid';
    final face = item['face'] as String?;
    final avatar = dense ? 48.0 : 44.0;

    final content = Row(
      children: [
        NetworkImgLayer(
          width: avatar,
          height: avatar,
          type: ImageType.avatar,
          src: face,
        ),
        SizedBox(width: dense ? 12 : 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                'UID: $mid',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '取消关注',
          icon: const Icon(Icons.person_remove_outlined),
          onPressed: () => onUnfollow(mid, name),
        ),
      ],
    );

    void open() => onOpen(item);
    void longUnfollow() => onUnfollow(mid, name);

    if (dense) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: open,
          onLongPress: longUnfollow,
          onSecondaryTap: PlatformUtils.isMobile ? null : longUnfollow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: content,
          ),
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: open,
        onLongPress: longUnfollow,
        onSecondaryTap: PlatformUtils.isMobile ? null : longUnfollow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: content,
        ),
      ),
    );
  }
}
