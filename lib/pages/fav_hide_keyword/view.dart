import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏/合集列表标题关键字隐藏管理
class FavHideKeywordPage extends StatefulWidget {
  const FavHideKeywordPage({super.key});

  @override
  State<FavHideKeywordPage> createState() => _FavHideKeywordPageState();
}

class _FavHideKeywordPageState extends State<FavHideKeywordPage> {
  late List<String> _list;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _list = List<String>.from(Pref.favHideKeywords);
    });
  }

  void _add() {
    final k = _controller.text.trim();
    if (k.isEmpty) {
      SmartDialog.showToast('请输入关键字');
      return;
    }
    Pref.addFavHideKeyword(k);
    _controller.clear();
    _refresh();
    SmartDialog.showToast('已添加');
  }

  void _remove(String k) {
    Pref.removeFavHideKeyword(k);
    _refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('隐藏关键字')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '输入标题关键字，包含即隐藏',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _add, child: const Text('添加')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '开启「收藏列表按关键字隐藏」后生效；匹配不区分大小写',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _list.isEmpty
                ? Center(
                    child: Text(
                      '暂无关键字',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  )
                : ListView.separated(
                    itemCount: _list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final k = _list[index];
                      return ListTile(
                        title: Text(k),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '删除',
                          onPressed: () => _remove(k),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
