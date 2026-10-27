import 'package:PiliPlus/utils/storage_pref.dart';

class GlobalData {
  int imgQuality = Pref.picQuality;

  num? coins;

  void afterCoin(num coin) {
    if (coins != null) {
      coins = coins! - coin;
    }
  }

  Set<int> blackMids = Pref.blackMids;

  List<Map> localFollowList = Pref.localFollows;
  List<Map> localSeasonList = Pref.localSeasons;
  List<Map> localPlaylistList = Pref.localPlaylists;
  List<Map> localVideoPlaylistList = Pref.localVideoPlaylist;
  List<Map> localVideoPlaylists = Pref.localVideoPlaylists;
  List<Map> localHistoryList = Pref.localHistory;
  List<Map> localLaterList = Pref.localLater;

  /// 连续播放本地列表时的临时备份，避免路由参数丢失导致播放侧栏空白
  List? pendingLocalMediaList;
  String? pendingLocalMediaTitle;
  Set<int> localFollowMids = {
    for (final e in Pref.localFollows)
      if (e['mid'] is int) e['mid'] as int
      else int.tryParse('${e['mid']}') ?? 0,
  }..remove(0);
  Set<int> localSeasonIds = {
    for (final e in Pref.localSeasons)
      if (e['id'] is int) e['id'] as int
      else int.tryParse('${e['id']}') ?? 0,
  }..remove(0);
  Set<int> localPlaylistIds = {
    for (final e in Pref.localPlaylists)
      if (e['mediaId'] is int) e['mediaId'] as int
      else int.tryParse('${e['mediaId']}') ?? 0,
  }..remove(0);

  bool dynamicsWaterfallFlow = Pref.dynamicsWaterfallFlow;

  bool showMedal = Pref.showMedal;

  // 私有构造函数
  GlobalData._();

  // 单例实例
  static final GlobalData _instance = GlobalData._();

  // 获取全局实例
  factory GlobalData() => _instance;
}

extension IterableExt<E> on Iterable<E> {
  Iterable<E> whereNotBlocked(Object? /* mid */ Function(E element) test) =>
      where((e) => !GlobalData().blackMids.contains(test(e)));
}
