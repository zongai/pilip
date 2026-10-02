import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:material_ui/material_ui.dart';

const double _kBtnSize = 44;

/// 将 [controller] 注册为当前子树的 PrimaryScrollController。
/// iOS 点击状态栏时会滚动该列表到顶部（原生行为）。
class PrimaryScrollScope extends StatelessWidget {
  const PrimaryScrollScope({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: controller,
      child: child,
    );
  }
}

/// 列表下滑后显示的「快速返回顶部」按钮。
/// 自身固定 44x44，未显示时为 [SizedBox.shrink]，不会遮挡下层。
class ScrollToTopButton extends StatefulWidget {
  const ScrollToTopButton({
    super.key,
    required this.controller,
    this.threshold,
    this.onPressed,
    this.heroTag,
    this.extraBottom = 0,
    this.extraRight = 0,
  });

  final ScrollController controller;
  final double? threshold;
  final VoidCallback? onPressed;
  final Object? heroTag;
  final double extraBottom;
  final double extraRight;

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _visible = false;

  double get _threshold {
    if (widget.threshold != null) return widget.threshold!;
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide < 600 ? 240.0 : 400.0;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(covariant ScrollToTopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      _onScroll();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) {
      if (_visible) setState(() => _visible = false);
      return;
    }
    final show = widget.controller.offset > _threshold;
    if (show != _visible) {
      setState(() => _visible = show);
    }
  }

  void _handleTap() {
    feedBack();
    if (widget.onPressed != null) {
      widget.onPressed!();
    } else {
      widget.controller.animToTop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }

    final padding = MediaQuery.paddingOf(context);
    final bottomPad = 12.0 + padding.bottom + widget.extraBottom;
    final rightPad = 12.0 + padding.right + widget.extraRight;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(right: rightPad, bottom: bottomPad),
      child: SizedBox(
        width: _kBtnSize,
        height: _kBtnSize,
        child: Material(
          elevation: 4,
          shadowColor: Colors.black45,
          shape: const CircleBorder(),
          color: scheme.primaryContainer,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _handleTap,
            child: Icon(
              Icons.vertical_align_top,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// 为列表启用 iOS 状态栏回顶，并在右下角叠放返回顶部按钮。
///
/// 使用 [Positioned.fill] 保证列表占满，按钮区域严格限制在右下角，
/// 避免任何全屏遮罩。
class ScrollToTopOverlay extends StatelessWidget {
  const ScrollToTopOverlay({
    super.key,
    required this.controller,
    required this.child,
    this.threshold,
    this.right = 0,
    this.bottom = 0,
    this.onPressed,
    this.heroTag,
    this.extraBottom = 0,
  });

  final ScrollController controller;
  final Widget child;
  final double? threshold;
  final double right;
  final double bottom;
  final VoidCallback? onPressed;
  final Object? heroTag;
  final double extraBottom;

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: controller,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 列表必须铺满，否则会出现空白/灰层
          Positioned.fill(child: child),
          // 按钮仅占右下角一小块；未显示时为 shrink，不拦截手势
          Positioned(
            right: right,
            bottom: bottom,
            width: _kBtnSize + 48 + extraBottom.clamp(0, 120),
            height: _kBtnSize + 48 + extraBottom.clamp(0, 120),
            child: Align(
              alignment: Alignment.bottomRight,
              child: ScrollToTopButton(
                controller: controller,
                threshold: threshold,
                onPressed: onPressed,
                heroTag: heroTag,
                extraBottom: extraBottom,
                extraRight: right,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 主框架内页面（有底部导航）建议额外抬高的距离。
double mainNavExtraBottom(BuildContext context) {
  if (Pref.useSideBar) return 0;
  final size = MediaQuery.sizeOf(context);
  if (size.isPortrait && size.shortestSide < 600) {
    return 72;
  }
  return 0;
}

bool get isApplePlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;
