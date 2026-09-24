import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/api_type.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get privacySettings => [
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
