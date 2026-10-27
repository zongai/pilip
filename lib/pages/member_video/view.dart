import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show ReloadScrollPhysics;
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/member/contribute_type.dart';
import 'package:PiliPlus/models_new/space/space_archive/item.dart';
import 'package:PiliPlus/pages/common/fab_mixin.dart';
import 'package:PiliPlus/pages/member/controller.dart';
import 'package:PiliPlus/pages/member_video/controller.dart';
import 'package:PiliPlus/pages/member_video/widgets/video_card_h_member_video.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get/get.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class MemberVideo extends StatefulWidget {
  const MemberVideo({
    super.key,
    required this.type,
    required this.heroTag,
    required this.mid,
    this.seasonId,
    this.seriesId,
    this.title,
    this.isSingle = false,
  });

  final ContributeType type;
  final String? heroTag;
  final int mid;
  final int? seasonId;
  final int? seriesId;
  final String? title;
  final bool isSingle;

  @override
  State<MemberVideo> createState() => _MemberVideoState();
}

class _MemberVideoState extends State<MemberVideo>
    with
        AutomaticKeepAliveClientMixin,
        GridMixin,
        SingleTickerProviderStateMixin,
        BaseFabMixin,
        LazyFabMixin {
  @override
  bool get wantKeepAlive => true;

  late final MemberVideoCtr _controller;
  bool _multiSelect = false;
  final Set<String> _selected = {};

  void _jumpToIndex(int index) {
    final scrollOffset = gridDelegate.layoutCache!
        .getGeometryForChildIndex(index)
        .scrollOffset;
    try {
      final state = Get.find<MemberController>(
        tag: widget.heroTag,
      ).scrollKey.currentState;
      if (state != null && state.mounted) {
        state.innerNestedPositions.first.localJumpTo(scrollOffset);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('jump error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = Get.put(
      MemberVideoCtr(
        heroTag: widget.heroTag,
        type: widget.type,
        mid: widget.mid,
        seasonId: widget.seasonId,
        seriesId: widget.seriesId,
        username: Get.find<MemberController>(tag: widget.heroTag).username,
        title: widget.title,
      ),
      tag:
          '${widget.heroTag}${widget.type.name}${widget.seasonId}${widget.seriesId}',
    );
  }

  Future<void> _loadPrevAndKeepPos() async {
    assert(_controller.hasPrev! && _controller.isLoadPrevious);
    final lastCount = _controller.loadingState.value.dataOrNull?.length;
    await _controller.queryData();
    if (mounted) {
      final newCount = _controller.loadingState.value.dataOrNull?.length;
      if (lastCount != null && newCount != null && newCount > lastCount) {
        _jumpToIndex(newCount - lastCount);
      }
    }
  }

  Future<void> _onRefresh() {
    if (_controller.isLoadPrevious) {
      return _loadPrevAndKeepPos();
    }
    return _controller.onRefresh();
  }

  @override
  Widget fabAnimWrapper({required Widget child}) {
    return NotificationListener<ScrollNotification>(
      onNotification: onNotification,
      child: child,
    );
  }

  @override
  bool onNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      return super.onNotification(notification);
    }
    if (_controller.isLocating) {
      if (notification is ScrollEndNotification &&
          notification.metrics.pixels == 0) {
        if (_controller.hasPrev == true && !_controller.isLoading) {
          _controller
            ..isLoadPrevious = true
            ..refreshKey!.currentState?.show();
        }
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    Widget child = CustomScrollView(
      physics: ReloadScrollPhysics(controller: _controller),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(bottom: padding.bottom + 100),
          sliver: Obx(
            () => _buildBody(theme, _controller.loadingState.value),
          ),
        ),
      ],
    );
    if (_controller.isVideo && _controller.fromViewAid?.isNotEmpty == true) {
      child = ScaffoldLayout(
        body: fabAnimWrapper(child: child),
        fab: Obx(
          () => !_controller.isLocating
              ? SlideTransition(
                  position: fabAnimation,
                  child: Padding(
                    padding: .only(
                      right: kFloatingActionButtonMargin,
                      bottom: kFloatingActionButtonMargin + padding.bottom,
                    ),
                    child: FloatingActionButton.extended(
                      onPressed: () {
                        final fromViewAid = _controller.fromViewAid;
                        final locatedIndex =
                            _controller.loadingState.value.dataOrNull
                                ?.indexWhere(
                                  (i) => i.param == fromViewAid,
                                ) ??
                            -1;
                        if (locatedIndex == -1) {
                          _controller
                            ..setIsLocating(true)
                            ..lastAid = fromViewAid
                            ..reload = true
                            ..page = 0
                            ..loadingState.value = LoadingState.loading()
                            ..queryData();
                        } else {
                          _controller.setIsLocating(
                            true,
                            isOnlyInnerScroll: false,
                          );
                          _jumpToIndex(locatedIndex);
                        }
                      },
                      label: const Text('定位至上次观看'),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      );
    }
    return refreshIndicator(
      key: _controller.refreshKey,
      isClampingScrollPhysics: true,
      onRefresh: _onRefresh,
      child: child,
    );
  }

  @override
  Widget get gridSkeleton => SliverPadding(
    padding: widget.isSingle ? const EdgeInsets.only(top: 7) : EdgeInsets.zero,
    sliver: super.gridSkeleton,
  );

  Widget _buildBody(
    ThemeData theme,
    LoadingState<List<SpaceArchiveItem>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverMainAxisGroup(
                slivers: [
                  _buildHeader(theme),
                  SliverGrid.builder(
                    gridDelegate: gridDelegate,
                    itemBuilder: (context, index) {
                      if (widget.type != .season &&
                          index == response.length - 1) {
                        _controller.onLoadMore();
                      }
                      final item = response[index];
                      final key = _itemKey(item);
                      final selected = _selected.contains(key);
                      return Stack(
                        children: [
                          VideoCardHMemberVideo(
                            videoItem: item,
                            fromViewAid: _controller.fromViewAid,
                            onTap: _multiSelect
                                ? () {
                                    setState(() {
                                      if (selected) {
                                        _selected.remove(key);
                                      } else if (key.isNotEmpty) {
                                        _selected.add(key);
                                      }
                                    });
                                  }
                                : null,
                          ),
                          if (_multiSelect)
                            Positioned(
                              left: 10,
                              top: 10,
                              child: IgnorePointer(
                                child: Material(
                                  color: Colors.black45,
                                  shape: const CircleBorder(),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      selected
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 22,
                                      color: selected
                                          ? theme.colorScheme.primary
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                    itemCount: response.length,
                  ),
                ],
              )
            : HttpError(onReload: _controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
    };
  }


  String _itemKey(SpaceArchiveItem item) =>
      item.bvid ?? item.param ?? '';

  List<SpaceArchiveItem> get _currentItems {
    if (_controller.loadingState.value case Success(:final response)) {
      if (response == null) return const [];
      return List<SpaceArchiveItem>.from(response);
    }
    return const [];
  }

  void _toggleMulti() {
    setState(() {
      _multiSelect = !_multiSelect;
      if (!_multiSelect) _selected.clear();
    });
  }

  void _selectAll() {
    final items = _currentItems;
    setState(() {
      if (_selected.length == items.length && items.isNotEmpty) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(items.map(_itemKey).where((k) => k.isNotEmpty));
      }
    });
  }

  Future<void> _addSelectedToPlaylist() async {
    final items = _currentItems
        .where((e) => _selected.contains(_itemKey(e)))
        .toList();
    if (items.isEmpty) {
      SmartDialog.showToast('请先选择视频');
      return;
    }
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }
    final pls = Pref.localVideoPlaylists;
    int? targetId;
    if (pls.isEmpty) {
      targetId = Pref.createLocalVideoPlaylist('默认列表');
    } else if (pls.length == 1) {
      targetId = asInt(pls.first['id']);
    } else {
      targetId = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择播放列表'),
          children: [
            for (final pl in pls)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, asInt(pl['id'])),
                child: Text(
                  '${pl['title']} (${(pl['items'] is List) ? (pl['items'] as List).length : 0})',
                ),
              ),
            SimpleDialogOption(
              onPressed: () {
                final id = Pref.createLocalVideoPlaylist('列表 ${pls.length + 1}');
                Navigator.pop(ctx, id);
              },
              child: const Text('+ 新建列表'),
            ),
          ],
        ),
      );
    }
    if (targetId == null) return;
    final maps = <Map>[];
    for (final e in items) {
      int? aid = asInt(e.param);
      String? bvid = e.bvid;
      if ((bvid == null || bvid.isEmpty) && aid != null) {
        try {
          bvid = IdUtils.av2bv(aid);
        } catch (_) {}
      }
      if (aid == null && bvid != null && bvid.isNotEmpty) {
        try {
          aid = IdUtils.bv2av(bvid);
        } catch (_) {}
      }
      if ((bvid == null || bvid.isEmpty) && aid == null) continue;
      maps.add({
        'aid': aid,
        'bvid': bvid,
        'cid': e.cid,
        'title': e.title,
        'cover': e.cover,
        'authorName': e.owner.name,
        'authorMid': (e.owner.mid == null || e.owner.mid == 0)
            ? widget.mid
            : e.owner.mid,
        'duration': e.duration > 0 ? e.duration : 0,
      });
    }
    if (maps.isEmpty) {
      SmartDialog.showToast('无法获取视频信息');
      return;
    }
    Pref.addLocalVideoPlaylistItems(
      maps,
      playlistId: targetId,
    );
    SmartDialog.showToast('已加入 ${items.length} 个视频');
    setState(() {
      _multiSelect = false;
      _selected.clear();
    });
  }

  Widget _buildHeader(ThemeData theme) {
    return SliverFloatingHeaderWidget(
      backgroundColor: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2.5, 8, 2.5),
        child: Row(
          children: [
            if (_multiSelect) ...[
              TextButton(
                style: Style.buttonStyle,
                onPressed: _selectAll,
                child: Text(
                  _selected.length == _currentItems.length &&
                          _currentItems.isNotEmpty
                      ? '取消全选'
                      : '全选',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              TextButton(
                style: Style.buttonStyle,
                onPressed: _addSelectedToPlaylist,
                child: Text(
                  '加入播放列表${_selected.isEmpty ? '' : '(${_selected.length})'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              TextButton(
                style: Style.buttonStyle,
                onPressed: _toggleMulti,
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ] else ...[
              ?_buildCount(),
              ?_buildEpisodeBtn(theme),
              const Spacer(),
              TextButton.icon(
                style: Style.buttonStyle,
                onPressed: _toggleMulti,
                icon: Icon(
                  Icons.checklist,
                  size: 16,
                  color: theme.colorScheme.secondary,
                ),
                label: Text(
                  '多选',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              _buildSortBtn(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _buildCount() {
    final count = _controller.count;
    if (count != null) {
      return Text(
        '共$count视频',
        style: const TextStyle(fontSize: 13),
      );
    }
    return null;
  }

  Widget? _buildEpisodeBtn(ThemeData theme) {
    final episodicButton = _controller.episodicButton;
    if (episodicButton?.uri?.isNotEmpty ?? false) {
      return Padding(
        padding: EdgeInsets.only(
          left: _controller.count != null ? 6 : 0,
        ),
        child: TextButton.icon(
          style: Style.buttonStyle,
          onPressed: _controller.toViewPlayAll,
          icon: Icon(
            Icons.play_circle_outline_rounded,
            size: 16,
            color: theme.colorScheme.secondary,
          ),
          label: Text(
            episodicButton?.text ?? '播放全部',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.secondary,
            ),
          ),
        ),
      );
    }
    return null;
  }

  Widget _buildSortBtn(ThemeData theme) {
    return TextButton.icon(
      style: Style.buttonStyle,
      onPressed: _controller.queryBySort,
      icon: Icon(
        Icons.sort,
        size: 16,
        color: theme.colorScheme.secondary,
      ),
      label: Text(
        _controller.isVideo ? _controller.order.label : _controller.sort.label,
        style: TextStyle(
          fontSize: 13,
          color: theme.colorScheme.secondary,
        ),
      ),
    );
  }
}
