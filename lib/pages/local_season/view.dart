import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地合集收藏：始终用固定高度卡片，避免 ListView 无界高度下 AspectRatio/Spacer 把条目压成 0
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
                final list = ListView.separated(
                  padding: EdgeInsets.only(
                    left: maxW >= 1000 ? 24 : 0,
                    right: maxW >= 1000 ? 24 : 0,
                    bottom: bottom + 24,
                  ),
                  itemCount: _list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _list[index];
                    return _SeasonCard(
                      item: item,
                      onOpen: _openSeason,
                      onUnfav: _unfav,
                    );
                  },
                );
                if (maxW < 720) return list;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxW >= 1200 ? 960 : 720,
                    ),
                    child: list,
                  ),
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

    // 固定高度，避免 ListView 子项无界高度导致封面/文字高度为 0
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => onOpen(item),
        onLongPress: id == 0 ? null : () => onUnfav(id, title),
        onSecondaryTap: PlatformUtils.isMobile || id == 0
            ? null
            : () => onUnfav(id, title),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 8,
          ),
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      NetworkImgLayer(
                        src: cover,
                        width: 120,
                        height: 72,
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
                const SizedBox(width: 12),
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
