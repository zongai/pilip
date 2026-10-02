import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:material_ui/material_ui.dart';

/// 列表下滑后显示的「快速返回顶部」按钮。
class ScrollToTopButton extends StatefulWidget {
  const ScrollToTopButton({
    super.key,
    required this.controller,
    this.threshold = 400,
    this.onPressed,
    this.heroTag,
  });

  final ScrollController controller;
  final double threshold;
  final VoidCallback? onPressed;
  final Object? heroTag;

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _visible = false;

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
    final show = widget.controller.offset > widget.threshold;
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
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: AnimatedScale(
          scale: _visible ? 1 : 0.8,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: FloatingActionButton.small(
            heroTag: widget.heroTag,
            tooltip: '返回顶部',
            onPressed: _handleTap,
            child: const Icon(Icons.vertical_align_top),
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
    this.threshold = 400,
    this.right = 16,
    this.bottom = 16,
    this.onPressed,
    this.heroTag,
  });

  final ScrollController controller;
  final Widget child;
  final double threshold;
  final double right;
  final double bottom;
  final VoidCallback? onPressed;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        child,
        Positioned(
          right: right + padding.right,
          bottom: bottom + padding.bottom,
          child: ScrollToTopButton(
            controller: controller,
            threshold: threshold,
            onPressed: onPressed,
            heroTag: heroTag,
          ),
        ),
      ],
    );
  }
}
