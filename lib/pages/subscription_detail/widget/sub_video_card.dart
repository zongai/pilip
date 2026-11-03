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

/// 合集/订阅视频卡片：已看置灰弱化，未看保持醒目
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

  bool get _watched =>
      Pref.enableLocalFeatures &&
      Pref.isLocalWatched(
        aid: videoItem.id,
        bvid: videoItem.bvid,
        duration: videoItem.duration,
      );

  @override
  Widget build(BuildContext context) {
    final watched = _watched;
    final outline = Theme.of(context).colorScheme.outline;

    void onLongPress() => imageSaveDialog(
          title: videoItem.title,
          cover: videoItem.cover,
          bvid: videoItem.bvid,
        );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () async {
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
        },
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Padding(
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
                        LocalWatchDim(
                          watched: watched,
                          child: NetworkImgLayer(
                            src: videoItem.cover,
                            width: maxWidth,
                            height: maxHeight,
                          ),
                        ),
                        // 图标始终保持清晰可点，不被置灰
                        Positioned(
                          left: 4,
                          top: 4,
                          child: LocalWatchToggleIcon(
                            aid: videoItem.id,
                            bvid: videoItem.bvid,
                            title: videoItem.title,
                            cover: videoItem.cover,
                            duration: videoItem.duration,
                            onChanged: (_) {
                              if (mounted) setState(() {});
                            },
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
                            text: DurationUtils.formatDuration(
                              videoItem.duration,
                            ),
                            right: 6.0,
                            bottom: 6.0,
                            type: PBadgeType.gray,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
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
            ],
          ),
        ),
      ),
    );
  }
}
