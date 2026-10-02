import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 列表下滑后显示的「快速返回顶部」按钮（桌面 / 移动端通用）。
class ScrollToTopButton extends StatefulWidget {
  const ScrollToTopButton({
    super.key,
    required this.controller,
    this.threshold,
    this.onPressed,
    this.heroTag,
    /// 额外上移，避开底部导航等（逻辑像素）
    this.extraBottom = 0,
    this.extraRight = 0,
  });

  final ScrollController controller;
  /// 触发显示的滚动阈值；为 null 时移动端更灵敏（约 240），桌面约 400
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
    // 移动端屏幕较短，更早出现按钮
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
    final padding = MediaQuery.paddingOf(context);
    // 移动端抬高，避免被系统手势条 / 底部导航挡住
    final bottomPad = 12.0 + padding.bottom + widget.extraBottom;
    final rightPad = 12.0 + padding.right + widget.extraRight;

    return Padding(
      padding: EdgeInsets.only(right: rightPad, bottom: bottomPad),
      child: IgnorePointer(
        ignoring: !_visible,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedScale(
            scale: _visible ? 1 : 0.85,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Material(
              elevation: _visible ? 4 : 0,
              shadowColor: Colors.black45,
              shape: const CircleBorder(),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _visible ? _handleTap : null,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.vertical_align_top,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 在 [child] 右下角叠放返回顶部按钮。
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: right,
          bottom: bottom,
          child: ScrollToTopButton(
            controller: controller,
            threshold: threshold,
            onPressed: onPressed,
            heroTag: heroTag,
            extraBottom: extraBottom,
            extraRight: right,
          ),
        ),
      ],
    );
  }
}

/// 主框架内页面（有底部导航）建议额外抬高的距离。
double mainNavExtraBottom(BuildContext context) {
  if (Pref.useSideBar) return 0;
  final size = MediaQuery.sizeOf(context);
  // 竖屏移动端底部导航约 64–80
  if (size.isPortrait && size.shortestSide < 600) {
    return 72;
  }
  return 0;
}
