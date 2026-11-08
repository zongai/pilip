import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/local_watch_toggle.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/media.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 合集/订阅视频卡片：已看置灰弱化；已看图标独立手势，不被整卡点击拦截
class SubVideoCardH extends StatefulWidget {
  final SubDetailItemModel videoItem;
  final int? searchType;

  const SubVideoCardH({
    super.key,
    required this.videoItem,
    this.searchType,
  });

  @override
  State<SubVideoCardH> createState() => _SubVideoCardHState();
}

class _SubVideoCardHState extends State<SubVideoCardH> {
  SubDetailItemModel get videoItem => widget.videoItem;

  /// 本地覆盖，保证点取消已看后立刻刷新置灰
  bool? _watchedOverride;

  bool get _watched {
    if (_watchedOverride != null) return _watchedOverride!;
    return Pref.enableLocalFeatures &&
        Pref.isLocalWatched(
          aid: videoItem.id,
          bvid: videoItem.bvid,
          duration: videoItem.duration,
        );
  }

  Future<void> _open() async {
    final res = await SearchHttp.ab2cWithDimension(bvid: videoItem.bvid);
    final cid = res?.cid;
    if (cid != null) {
      PageUtils.toVideoPage(
        bvid: videoItem.bvid,
        cid: cid,
        cover: videoItem.cover,
        title: videoItem.title,
        dimension: res!.dimension,
      );
    }
  }

  void _onLongPress() => imageSaveDialog(
        title: videoItem.title,
        cover: videoItem.cover,
        bvid: videoItem.bvid,
      );

  @override
  Widget build(BuildContext context) {
    final watched = _watched;
    final outline = Theme.of(context).colorScheme.outline;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Style.safeSpace,
        vertical: 5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: Style.aspectRatio,
            child: LayoutBuilder(
              builder: (context, boxConstraints) {
                final maxWidth = boxConstraints.maxWidth;
                final maxHeight = boxConstraints.maxHeight;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 仅封面置灰，不含手势（避免 ColorFiltered/整卡手势干扰图标）
                    LocalWatchDim(
                      watched: watched,
                      child: NetworkImgLayer(
                        src: videoItem.cover,
                        width: maxWidth,
                        height: maxHeight,
                      ),
                    ),
                    // 封面打开视频：translucent，不抢子组件点击
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _open,
                        onLongPress: _onLongPress,
                        onSecondaryTap:
                            PlatformUtils.isMobile ? null : _onLongPress,
                      ),
                    ),
                    LocalWatchProgressBar(
                      aid: videoItem.id,
                      bvid: videoItem.bvid,
                      duration: videoItem.duration,
                    ),
                    LocalWatchDim(
                      watched: watched,
                      opacity: 0.65,
                      child: PBadge(
                        text: DurationUtils.formatDuration(videoItem.duration),
                        right: 6.0,
                        bottom: 6.0,
                        type: PBadgeType.gray,
                      ),
                    ),
                    // 图标必须在 Stack 最后，保证已看置灰后仍可点
                    Positioned(
                      left: 0,
                      top: 0,
                      child: LocalWatchToggleIcon(
                        aid: videoItem.id,
                        bvid: videoItem.bvid,
                        title: videoItem.title,
                        cover: videoItem.cover,
                        duration: videoItem.duration,
                        size: 22,
                        padding: const EdgeInsets.all(8),
                        onChanged: (nowWatched) {
                          if (mounted) {
                            setState(() => _watchedOverride = nowWatched);
                          }
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _open,
              onLongPress: _onLongPress,
              onSecondaryTap: PlatformUtils.isMobile ? null : _onLongPress,
              child: LocalWatchDim(
                watched: watched,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        videoItem.title!,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          letterSpacing: 0.3,
                          color: watched ? outline : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      DateFormatUtils.dateFormat(videoItem.pubtime),
                      style: TextStyle(fontSize: 12, color: outline),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      spacing: 8,
                      children: [
                        StatWidget(
                          type: StatType.play,
                          value: videoItem.cntInfo?.play,
                        ),
                        StatWidget(
                          type: StatType.danmaku,
                          value: videoItem.cntInfo?.danmaku,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
