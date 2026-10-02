import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:material_ui/material_ui.dart';

const double _kBtnSize = 44;

/// 将 [controller] 注册为当前子树的 PrimaryScrollController。
///
/// 在 iOS 上点击状态栏时，系统会滚动 PrimaryScrollController 对应的列表到顶部
/// （与原生 App 行为一致）。桌面端同样可用于键盘快捷键等。
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

/// 列表下滑后显示的「快速返回顶部」按钮（桌面 / 移动端通用）。
///
/// 注意：在 Stack/Positioned 中必须限制自身尺寸，否则 Material 会被撑满全屏。
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
    final padding = MediaQuery.paddingOf(context);
    final bottomPad = 12.0 + padding.bottom + widget.extraBottom;
    final rightPad = 12.0 + padding.right + widget.extraRight;
    final scheme = Theme.of(context).colorScheme;

    if (!_visible) {
      return const SizedBox.shrink();
    }

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

/// 在 [child] 右下角叠放返回顶部按钮，并把 [controller] 设为 PrimaryScrollController
/// （支持 iOS 点状态栏回到顶部）。
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
        fit: StackFit.passthrough,
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

/// 是否为 iOS / iPadOS 平台（状态栏点按回顶为系统行为）。
bool get isApplePlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;
