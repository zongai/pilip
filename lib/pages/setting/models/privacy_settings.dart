import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/accounts/api_type.dart';
import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get privacySettings => [
  SwitchModel(
    title: '启用本地功能',
    subtitle: '开启后使用本地关注/黑名单/合集等；关闭后界面恢复原始样式并显示动态页（需重启）',
    leading: const Icon(Icons.phone_android_outlined),
    setKey: SettingBoxKey.enableLocalFeatures,
    defaultVal: true,
    needReboot: true,
  ),
  if (Pref.enableLocalFeatures) ...[
    NormalModel(
      onTap: (context, setState) {
        Get.toNamed('/localBlackListPage');
      },
      title: '黑名单管理',
      subtitle: '本地屏蔽UP主，相关内容自动隐藏（无需登录）',
      leading: const Icon(Icons.block),
    ),
    NormalModel(
      onTap: (context, setState) {
        Get.toNamed('/localFollowPage');
      },
      title: '本地关注',
      subtitle: '无需登录的关注列表',
      leading: const Icon(Icons.favorite_border),
    ),
    SwitchModel(
      title: '短视频默认已看',
      subtitle: '时长短于 3 分钟的视频在列表中默认标为已看完，仍可手动改未看',
      leading: const Icon(Icons.timer_outlined),
      setKey: SettingBoxKey.autoWatchShortVideos,
      defaultVal: true,
    ),
    SwitchModel(
      title: '收藏列表按关键字隐藏',
      subtitle: '标题包含关键字的视频在收藏/合集中隐藏',
      leading: const Icon(Icons.filter_alt_outlined),
      setKey: SettingBoxKey.hideFavByKeywords,
      defaultVal: false,
    ),
    NormalModel(
      title: '隐藏关键字管理',
      getSubtitle: () {
        final n = Pref.favHideKeywords.length;
        return n == 0 ? '未添加关键字' : '已添加 $n 个关键字';
      },
      leading: const Icon(Icons.manage_search_outlined),
      onTap: (context, setState) async {
        await Get.toNamed('/favHideKeywordPage');
        setState();
      },
    ),
    NormalModel(
      onTap: (context, setState) {
        Get.toNamed('/localSeasonPage');
      },
      title: '合集收藏',
      subtitle: '本地订阅合集，无需登录，可在此管理',
      leading: const Icon(Icons.video_library_outlined),
    ),
    NormalModel(
      onTap: (context, setState) {
        _showLocalDataIoSheet(context);
      },
      title: '本地数据导入导出',
      subtitle:
          '全部数据一次导入导出（含搜索历史）',
      leading: const Icon(Icons.import_export),
    ),
  ],
  NormalModel(
    onTap: (context, setState) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('账号模式详情'),
          content: SelectionArea(
            child: SingleChildScrollView(
              child: _getAccountDetail(context),
            ),
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: const Text('确认'),
            ),
          ],
        ),
      );
    },
    leading: const Icon(Icons.flag_outlined),
    title: '了解账号模式',
    subtitle: '查看各个账号模式作用的API列表',
  ),
];

void _showLocalDataIoSheet(BuildContext context) {
  final theme = Theme.of(context);
  final followCount = Pref.localFollows.length;
  final blackCount = Pref.blackMids.length;
  final playlistCount = Pref.localPlaylists.length;
  final historyCount = Pref.localHistory.length;
  final laterCount = Pref.localLater.length;
  final searchCount = LocalListIo.searchHistoryList.length;
  final seasonCount = Pref.localSeasons.length;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '本地数据导入导出',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '关注 $followCount · 黑名单 $blackCount · 播单 $playlistCount · '
                  '合集 $seasonCount · 历史 $historyCount · 稍后再看 $laterCount · '
                  '搜索 $searchCount',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.upload_outlined),
                title: const Text('全部导出'),
                subtitle: const Text('打包为单个 JSON 文件'),
                onTap: () {
                  Navigator.pop(context);
                  LocalListIo.exportAll();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('全部导入（合并）'),
                subtitle: const Text('与现有数据合并，不删除旧数据'),
                onTap: () {
                  Navigator.pop(context);
                  LocalListIo.importAll();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('全部导入（覆盖）'),
                subtitle: const Text('用备份替换对应类别数据'),
                onTap: () {
                  Navigator.pop(context);
                  LocalListIo.importAll(replace: true);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    },
  );
}

Widget _getAccountDetail(BuildContext context) {
  final children = <Widget>[];
  final theme = TextTheme.of(context);
  for (final i in AccountType.values) {
    final url = ApiType.apiTypeSet[i];
    if (url == null) continue;

    children
      ..add(Center(child: Text(i.title, style: theme.titleMedium)))
      ..add(Text(url.join('\n')));
  }
  return Column(
    spacing: 8,
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    children: children,
  );
}
