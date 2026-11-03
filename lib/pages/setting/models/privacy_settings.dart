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
          '关注 · 黑名单 · 播单 · 历史 · 稍后再看（JSON 备份）',
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
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      Widget section(String title, List<Widget> children) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            ...children,
          ],
        );
      }

      Widget action(String label, VoidCallback onTap) {
        return ListTile(
          title: Text(label),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );
      }

      final followCount = Pref.localFollows.length;
      final blackCount = Pref.blackMids.length;
      final playlistCount = Pref.localPlaylists.length;
      final historyCount = Pref.localHistory.length;
      final laterCount = Pref.localLater.length;

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
              section('关注（$followCount）', [
                action('导出关注', LocalListIo.exportFollows),
                action('导入关注（合并）', () => LocalListIo.importFollows()),
                action(
                  '导入关注（覆盖）',
                  () => LocalListIo.importFollows(replace: true),
                ),
              ]),
              const Divider(height: 1),
              section('黑名单（$blackCount）', [
                action('导出黑名单', LocalListIo.exportBlacklist),
                action('导入黑名单（合并）', () => LocalListIo.importBlacklist()),
                action(
                  '导入黑名单（覆盖）',
                  () => LocalListIo.importBlacklist(replace: true),
                ),
              ]),
              const Divider(height: 1),
              section('播放列表（$playlistCount）', [
                action('导出播放列表', LocalListIo.exportPlaylists),
                action('导入播放列表（合并）', () => LocalListIo.importPlaylists()),
                action(
                  '导入播放列表（覆盖）',
                  () => LocalListIo.importPlaylists(replace: true),
                ),
              ]),
              const Divider(height: 1),
              section('观看历史（$historyCount）', [
                action('导出历史', LocalListIo.exportHistory),
                action('导入历史（合并）', () => LocalListIo.importHistory()),
                action(
                  '导入历史（覆盖）',
                  () => LocalListIo.importHistory(replace: true),
                ),
              ]),
              const Divider(height: 1),
              section('稍后再看（$laterCount）', [
                action('导出稍后再看', LocalListIo.exportLater),
                action('导入稍后再看（合并）', () => LocalListIo.importLater()),
                action(
                  '导入稍后再看（覆盖）',
                  () => LocalListIo.importLater(replace: true),
                ),
              ]),
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
