import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地合集收藏（无需登录），按窗口宽度自适应列表/网格
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
    Get.toNamed(
      '/subDetail',
      arguments: {
        'id': id,
        'heroTag': 'local_season_$id',
      },
      parameters: {
        'id': '$id',
        'type': '2',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text('合集收藏${_list.isEmpty ? '' : ' · ${_list.length}'}'),
      ),
      body: _list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
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
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                // 窄屏单列；≥600 起多列，桌面/平板更宽时列数随 maxCrossAxisExtent 自动增加
                final useGrid = width >= 600;
                final padding = EdgeInsets.only(
                  left: width >= 1000 ? 24 : 0,
                  right: width >= 1000 ? 24 : 0,
                  bottom: bottom + 24,
                );

                if (!useGrid) {
                  return ListView.builder(
                    padding: padding,
                    itemCount: _list.length,
                    itemBuilder: (context, index) =>
                        _SeasonCard(item: _list[index], onOpen: _openSeason, onUnfav: _unfav),
                  );
                }

                return GridView.builder(
                  padding: padding,
                  gridDelegate: Grid.videoCardHDelegate(mainAxisExtent: 120),
                  itemCount: _list.length,
                  itemBuilder: (context, index) =>
                      _SeasonCard(item: _list[index], onOpen: _openSeason, onUnfav: _unfav),
                );
              },
            ),
    );
  }
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    required this.item,
    required this.onOpen,
    required this.onUnfav,
  });

  final Map item;
  final void Function(Map item) onOpen;
  final void Function(int id, String title) onUnfav;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = item['id'] as int? ?? 0;
    final title = (item['title'] as String?)?.isNotEmpty == true
        ? item['title'] as String
        : '合集 $id';
    final cover = item['cover'] as String?;
    final mediaCount = item['mediaCount'];
    final upperName = (item['upperName'] as String?)?.trim() ?? '';
    final countText = mediaCount is int && mediaCount > 0 ? '$mediaCount 集' : null;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => onOpen(item),
        onLongPress: () => onUnfav(id, title),
        onSecondaryTap: PlatformUtils.isMobile ? null : () => onUnfav(id, title),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 6,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: Style.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, box) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        NetworkImgLayer(
                          src: cover,
                          width: box.maxWidth,
                          height: box.maxHeight,
                        ),
                        if (countText != null)
                          PBadge(
                            text: countText,
                            bottom: 6,
                            right: 6,
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    if (upperName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        upperName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: '取消收藏',
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: Icon(
                          Icons.notifications_off_outlined,
                          color: theme.colorScheme.outline,
                        ),
                        onPressed: () => onUnfav(id, title),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
