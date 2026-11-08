import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 灰度矩阵：已看内容弱化，突出未看
const ColorFilter kWatchedGrayFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// 已看时弱化子组件（透明度 + 灰度），未看保持原样
class LocalWatchDim extends StatelessWidget {
  const LocalWatchDim({
    super.key,
    required this.watched,
    required this.child,
    this.opacity = 0.52,
  });

  final bool watched;
  final Widget child;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (!watched) return child;
    return Opacity(
      opacity: opacity,
      child: ColorFiltered(
        colorFilter: kWatchedGrayFilter,
        child: child,
      ),
    );
  }
}

/// 本地已看/未看切换图标（点击切换状态）
class LocalWatchToggleIcon extends StatefulWidget {
  const LocalWatchToggleIcon({
    super.key,
    this.aid,
    this.bvid,
    this.cid,
    this.title,
    this.cover,
    this.authorName,
    this.authorMid,
    this.duration,
    this.size = 18,
    this.padding = const EdgeInsets.all(5),
    this.onChanged,
  });

  final int? aid;
  final String? bvid;
  final int? cid;
  final String? title;
  final String? cover;
  final String? authorName;
  final int? authorMid;
  final int? duration;
  final double size;
  final EdgeInsets padding;
  final ValueChanged<bool>? onChanged;

  @override
  State<LocalWatchToggleIcon> createState() => _LocalWatchToggleIconState();
}

class _LocalWatchToggleIconState extends State<LocalWatchToggleIcon> {
  /// 乐观更新，避免 Pref 异步/重建导致图标瞬间回弹
  bool? _overrideWatched;

  bool get _watchedFromPref =>
      Pref.getLocalWatchProgress(
        aid: widget.aid,
        bvid: widget.bvid,
        duration: widget.duration,
      ) !=
      null;

  bool get _watched => _overrideWatched ?? _watchedFromPref;

  void _toggle() {
    final currentlyWatched = _watched;
    if (currentlyWatched) {
      Pref.markLocalUnwatched(aid: widget.aid, bvid: widget.bvid);
      // 校验：若仍被判定为已看，再强制写一次覆盖
      if (Pref.isLocalWatched(
        aid: widget.aid,
        bvid: widget.bvid,
        duration: widget.duration,
      )) {
        Pref.markLocalUnwatched(aid: widget.aid, bvid: widget.bvid);
      }
      _overrideWatched = false;
      SmartDialog.showToast('已标为未看');
    } else {
      Pref.markLocalWatched(
        aid: widget.aid,
        bvid: widget.bvid,
        cid: widget.cid,
        title: widget.title,
        cover: widget.cover,
        authorName: widget.authorName,
        authorMid: widget.authorMid,
        duration: widget.duration,
        completed: true,
      );
      _overrideWatched = true;
      SmartDialog.showToast('已标为已看完');
    }
    if (mounted) setState(() {});
    widget.onChanged?.call(!currentlyWatched);
  }

  @override
  Widget build(BuildContext context) {
    if (!Pref.enableLocalFeatures) return const SizedBox.shrink();
    final colorScheme = ColorScheme.of(context);
    final watched = _watched;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Material(
        color: watched
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.9)
            : Colors.black54,
        shape: const CircleBorder(),
        elevation: 2,
        child: Padding(
          padding: widget.padding,
          child: Icon(
            watched ? Icons.check_circle : Icons.radio_button_unchecked,
            size: widget.size,
            color: watched ? colorScheme.primary : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 底部进度条（有具体进度时显示）
class LocalWatchProgressBar extends StatelessWidget {
  const LocalWatchProgressBar({
    super.key,
    this.aid,
    this.bvid,
    this.duration,
  });

  final int? aid;
  final String? bvid;
  final int? duration;

  @override
  Widget build(BuildContext context) {
    if (!Pref.enableLocalFeatures) return const SizedBox.shrink();
    final progress = Pref.getLocalWatchProgress(
      aid: aid,
      bvid: bvid,
      duration: duration,
    );
    final dur = duration ?? 0;
    if (progress == null || progress == 0 || dur <= 0) {
      return const SizedBox.shrink();
    }
    final colorScheme = ColorScheme.of(context);
    final value = progress == -1 ? 1.0 : (progress / dur).clamp(0.0, 1.0);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: LinearProgressIndicator(
        value: value,
        minHeight: 3,
        backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        color: colorScheme.primary.withValues(alpha: 0.85),
      ),
    );
  }
}
