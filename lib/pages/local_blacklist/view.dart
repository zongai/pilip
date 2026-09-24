import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 黑名单管理（无需登录）
class LocalBlackListPage extends StatefulWidget {
  const LocalBlackListPage({super.key});

  @override
  State<LocalBlackListPage> createState() => _LocalBlackListPageState();
}

class _LocalBlackListPageState extends State<LocalBlackListPage> {
  late List<int> _mids;

  @override
  void initState() {
    super.initState();
    _mids = GlobalData().blackMids.toList()..sort();
  }

  void _refresh() {
    setState(() {
      _mids = GlobalData().blackMids.toList()..sort();
    });
  }

  void _remove(int mid) {
    Pref.removeBlackMid(mid);
    SmartDialog.showToast('已移出黑名单 $mid');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('黑名单管理${_mids.isEmpty ? '' : ': ${_mids.length}'}'),
      ),
      body: _mids.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '黑名单为空',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在用户主页或动态中「加入黑名单」\n加入后相关推荐、动态等内容将自动隐藏（无需登录）',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _mids.length,
              itemBuilder: (context, index) {
                final mid = _mids[index];
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text('UID: $mid'),
                  subtitle: const Text('点击查看主页'),
                  onTap: () => Get.toNamed('/member?mid=$mid'),
                  trailing: IconButton(
                    tooltip: '移出黑名单',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(mid),
                  ),
                );
              },
            ),
    );
  }
}
