import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地合集收藏：按页面宽度自适应列表 / 多列网格
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

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  void _unfav(int id, String title) {
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
              Pref.removeLocalSeason(id);
              SmartDialog.showToast('已取消收藏 $title');
              _refresh();
            },
            child: const Text('确定取消'),
          ),
        ],
      ),
    );
  }

  void _openSeason(Map item) {
    final id = _asInt(item['id']);
    if (id == null) {
      SmartDialog.showToast('无法识别合集 ID');
      return;
    }
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
    final hPad = MediaQuery.viewPaddingOf(context).horizontal;

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
                      '在合集选集面板点击「订阅」即可添加\n加入后可在此管理',
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
                // 断点：手机单列；平板双列；桌面多列（限制最大内容宽，避免超宽拉伸）
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
                  top: 4,
                  bottom: bottom + 24,
                );

                Widget child;
                if (!useGrid) {
                  child = ListView.separated(
                    padding: padding,
                    itemCount: _list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => _SeasonCard(
                      item: _list[index],
                      dense: true,
                      onOpen: _openSeason,
                      onUnfav: _unfav,
                    ),
                  );
                } else {
                  // 列宽约 280–320，行高固定，避免 0 高度
                  final crossExtent = maxW >= 1100 ? 300.0 : 280.0;
                  child = GridView.builder(
                    padding: padding,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: crossExtent,
                      mainAxisExtent: 88,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: _list.length,
                    itemBuilder: (context, index) => _SeasonCard(
                      item: _list[index],
                      dense: false,
                      onOpen: _openSeason,
                      onUnfav: _unfav,
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
    );
  }
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    required this.item,
    required this.onOpen,
    required this.onUnfav,
    this.dense = true,
  });

  final Map item;
  final void Function(Map item) onOpen;
  final void Function(int id, String title) onUnfav;
  final bool dense;

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = _asInt(item['id']) ?? 0;
    final title = (item['title'] as String?)?.isNotEmpty == true
        ? item['title'] as String
        : '合集 $id';
    final cover = item['cover']?.toString();
    final mediaCount = _asInt(item['mediaCount']);
    final upperName = (item['upperName'] as String?)?.trim() ?? '';
    final countText =
        mediaCount != null && mediaCount > 0 ? '$mediaCount 集' : null;

    final coverW = dense ? 120.0 : 110.0;
    final coverH = dense ? 72.0 : 68.0;

    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onOpen(item),
        onLongPress: id == 0 ? null : () => onUnfav(id, title),
        onSecondaryTap: PlatformUtils.isMobile || id == 0
            ? null
            : () => onUnfav(id, title),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? Style.safeSpace : 6,
            vertical: dense ? 8 : 6,
          ),
          child: SizedBox(
            height: coverH,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      NetworkImgLayer(
                        src: cover,
                        width: coverW,
                        height: coverH,
                      ),
                      if (countText != null)
                        PBadge(
                          text: countText,
                          bottom: 4,
                          right: 4,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.3,
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
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '取消收藏',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: Icon(
                    Icons.star,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: id == 0 ? null : () => onUnfav(id, title),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
