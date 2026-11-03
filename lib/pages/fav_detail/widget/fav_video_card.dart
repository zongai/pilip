import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/local_watch_toggle.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/select_mask.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pbenum.dart'
    show PlaylistSource;
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/fav/fav_detail/media.dart';
import 'package:PiliPlus/pages/audio/view.dart';
import 'package:PiliPlus/pages/fav_detail/controller.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

// 收藏视频卡片 - 水平布局（支持本地已看/未看标注与手动管理）
class FavVideoCardH extends StatefulWidget {
  final FavDetailItemModel item;
  final int? index;
  final BaseFavController? ctr;

  const FavVideoCardH({
    super.key,
    required this.item,
    this.index,
    this.ctr,
  }) : assert(ctr == null || index != null);

  @override
  State<FavVideoCardH> createState() => _FavVideoCardHState();
}

class _FavVideoCardHState extends State<FavVideoCardH> {
  FavDetailItemModel get item => widget.item;
  int? get index => widget.index;
  BaseFavController? get ctr => widget.ctr;
  bool get isSort => ctr == null;

  void _onTap() {
    // 0/4/16/...: 正常；9: up自己删除；1: 其他原因删除
    if (const [1, 9].contains(item.attr)) {
      Get.toNamed('/member?mid=${item.upper?.mid}');
      return;
    }

    switch (item.type) {
      case 12:
        AudioPage.toAudioPage(
          oid: item.id!,
          itemType: 3,
          from: PlaylistSource.AUDIO_CARD,
        );
        break;
      case 24:
        PageUtils.viewPgc(
          seasonId: item.ogv!.seasonId,
          epId: item.id,
        );
        break;
      default:
        ctr!.onViewFav(item, index);
        break;
    }
  }


  void _showWatchManage(BuildContext context) {
    final watched = Pref.isLocalWatched(aid: item.id, bvid: item.bvid, duration: item.duration);
    final progress = Pref.getLocalWatchProgress(
      aid: item.id,
      bvid: item.bvid,
      duration: item.duration,
    );
    final isOwner = !isSort && (ctr?.isOwner ?? false);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  item.title ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('管理'),
              ),
              const Divider(height: 1),
              if (Pref.enableLocalFeatures) ...[
                if (progress != -1)
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: const Text('标为已看完'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Pref.markLocalWatched(
                        aid: item.id,
                        bvid: item.bvid,
                        title: item.title,
                        cover: item.cover,
                        authorName: item.upper?.name,
                        authorMid: item.upper?.mid,
                        duration: item.duration,
                        completed: true,
                      );
                      SmartDialog.showToast('已标为已看完');
                      if (mounted) setState(() {});
                    },
                  ),
                if (watched)
                  ListTile(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: const Text('标为未看'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Pref.markLocalUnwatched(aid: item.id, bvid: item.bvid);
                      SmartDialog.showToast('已标为未看');
                      if (mounted) setState(() {});
                    },
                  ),
              ],
              if (isOwner)
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: const Text('多选'),
                  onTap: () {
                    Navigator.pop(ctx);
                    ctr!
                      ..enableMultiSelect.value = true
                      ..onSelect(item);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('保存封面'),
                onTap: () {
                  Navigator.pop(ctx);
                  imageSaveDialog(
                    title: item.title,
                    cover: item.cover,
                    bvid: item.bvid,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = !isSort && ctr!.isOwner;
    late final enableMultiSelect = ctr?.enableMultiSelect.value ?? false;
    final colorScheme = ColorScheme.of(context);

    void openImageSave() => imageSaveDialog(
          title: item.title,
          cover: item.cover,
          bvid: item.bvid,
        );

    void onLongPressAction() {
      if (isSort || enableMultiSelect) return;
      if (Pref.enableLocalFeatures) {
        _showWatchManage(context);
        return;
      }
      if (isOwner) {
        ctr!
          ..enableMultiSelect.value = true
          ..onSelect(item);
        return;
      }
      openImageSave();
    }

    final onLongPress =
        isSort || enableMultiSelect ? null : onLongPressAction;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: isSort
            ? null
            : enableMultiSelect
            ? () => ctr!.onSelect(item)
            : _onTap,
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
                    double maxWidth = boxConstraints.maxWidth;
                    double maxHeight = boxConstraints.maxHeight;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        LocalWatchDim(
                          watched: watched,
                          child: NetworkImgLayer(
                            src: item.cover,
                            width: maxWidth,
                            height: maxHeight,
                          ),
                        ),
                        // 图标始终清晰可点
                        if (Pref.enableLocalFeatures) ...[
                          Positioned(
                            left: 4,
                            top: 4,
                            child: LocalWatchToggleIcon(
                              aid: item.id,
                              bvid: item.bvid,
                              title: item.title,
                              cover: item.cover,
                              authorName: item.upper?.name,
                              authorMid: item.upper?.mid,
                              duration: item.duration,
                              onChanged: (_) {
                                if (mounted) setState(() {});
                              },
                            ),
                          ),
                          LocalWatchProgressBar(
                            aid: item.id,
                            bvid: item.bvid,
                            duration: item.duration,
                          ),
                        ],
                        PBadge(
                          text: DurationUtils.formatDuration(item.duration),
                          right: 6.0,
                          bottom: 6.0,
                          type: PBadgeType.gray,
                        ),
                        if (item.type == 12)
                          const PBadge(
                            text: '音频',
                            top: 6.0,
                            right: 6.0,
                            type: PBadgeType.gray,
                          )
                        else
                          PBadge(
                            text: item.ogv?.typeName,
                            top: 6.0,
                            right: 6.0,
                            bottom: null,
                            left: null,
                          ),
                        if (!isSort)
                          Positioned.fill(
                            child: selectMask(
                              colorScheme,
                              item.checked,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              content(context, colorScheme, isOwner, watched),
            ],
          ),
        ),
      ),
    );
  }

  Widget content(BuildContext context, ColorScheme colorScheme, bool isOwner, bool watched) {
    return Expanded(
      child: LocalWatchDim(
        watched: watched,
        child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            spacing: 3,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title!,
                textAlign: TextAlign.start,
                style: TextStyle(
                  letterSpacing: 0.3,
                  color: watched ? colorScheme.outline : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.type == 24 && item.intro?.isNotEmpty == true)
                Text(
                  item.intro!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                  ),
                ),
              const Spacer(),
              Text(
                '${DateFormatUtils.dateFormat(item.favTime)} ${item.upper?.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  height: 1,
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
              if (item.type != 24)
                Row(
                  spacing: 8,
                  children: [
                    StatWidget(
                      type: StatType.play,
                      value: item.cntInfo?.play,
                    ),
                    StatWidget(
                      type: StatType.danmaku,
                      value: item.cntInfo?.danmaku,
                    ),
                  ],
                ),
            ],
          ),
          if (isOwner)
            Positioned(
              right: 0,
              bottom: -8,
              child: iconButton(
                icon: const Icon(Icons.clear),
                tooltip: '取消收藏',
                iconColor: colorScheme.outline,
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('提示'),
                    content: const Text('要取消收藏吗?'),
                    actions: [
                      TextButton(
                        onPressed: Get.back,
                        child: Text(
                          '取消',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Get.back();
                          ctr!.onCancelFav(index!, item.id!, item.type!);
                        },
                        child: const Text('确定取消'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}
