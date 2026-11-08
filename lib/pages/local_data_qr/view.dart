import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// 本地数据二维码多端同步
class LocalDataQrPage extends StatefulWidget {
  const LocalDataQrPage({super.key});

  @override
  State<LocalDataQrPage> createState() => _LocalDataQrPageState();
}

class _LocalDataQrPageState extends State<LocalDataQrPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  List<String> _chunks = const [];
  int _index = 0;
  final _pasteCtrl = TextEditingController();
  final _received = <int, String>{};
  int? _expectedTotal;
  bool _replace = false;

  @override
  void initState() {
    super.initState();
    _rebuildChunks();
  }

  void _rebuildChunks() {
    setState(() {
      _chunks = LocalListIo.buildQrChunks();
      _index = 0;
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _importTexts(List<String> texts) async {
    final ok = await LocalListIo.importFromQrTexts(
      texts,
      replace: _replace,
    );
    if (ok && mounted) {
      setState(() {
        _received.clear();
        _expectedTotal = null;
        _pasteCtrl.clear();
      });
    }
  }

  void _ingestPasted(String text) {
    final lines = text
        .split(RegExp(r'[\n\r]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      SmartDialog.showToast('请粘贴同步内容');
      return;
    }
    // 单段完整或 JSON
    if (lines.length == 1 && !lines.first.startsWith('${LocalListIo.qrPrefix}|')) {
      _importTexts(lines);
      return;
    }
    for (final line in lines) {
      if (!line.startsWith('${LocalListIo.qrPrefix}|')) continue;
      final segs = line.split('|');
      if (segs.length < 4) continue;
      final idx = int.tryParse(segs[1]);
      final tot = int.tryParse(segs[2]);
      if (idx == null || tot == null) continue;
      _expectedTotal = tot;
      _received[idx] = line;
    }
    setState(() {});
    final total = _expectedTotal ?? 0;
    if (total > 0 && _received.length >= total) {
      _importTexts(_received.values.toList());
    } else if (total > 0) {
      SmartDialog.showToast('已收 ${_received.length}/$total 段，请继续粘贴');
    } else {
      _importTexts(lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('二维码同步'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '导出'),
            Tab(text: '导入'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新数据',
            onPressed: _rebuildChunks,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildExport(theme),
          _buildImport(theme),
        ],
      ),
    );
  }

  Widget _buildExport(ThemeData theme) {
    if (_chunks.isEmpty) {
      return const Center(child: Text('无数据'));
    }
    final chunk = _chunks[_index.clamp(0, _chunks.length - 1)];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '用另一台设备「导入」页扫描或手动输入下方内容',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '共 ${_chunks.length} 段 · 当前第 ${_index + 1} 段',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: 260,
              height: 260,
              child: PrettyQrView.data(
                data: chunk,
                decoration: const PrettyQrDecoration(
                  shape: PrettyQrSquaresSymbol(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: _index > 0
                  ? () => setState(() => _index--)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 12),
            Text('${_index + 1} / ${_chunks.length}'),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: _index < _chunks.length - 1
                  ? () => setState(() => _index++)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: chunk));
            SmartDialog.showToast('已复制当前段');
          },
          icon: const Icon(Icons.copy),
          label: const Text('复制当前段文本'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: _chunks.join('\n')),
            );
            SmartDialog.showToast('已复制全部 ${_chunks.length} 段');
          },
          icon: const Icon(Icons.copy_all),
          label: const Text('复制全部段'),
        ),
        const SizedBox(height: 12),
        Text(
          '数据较大时会自动分成多段二维码，请按顺序扫描或复制。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildImport(ThemeData theme) {
    final total = _expectedTotal;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('覆盖导入'),
          subtitle: const Text('关闭则与现有数据合并'),
          value: _replace,
          onChanged: (v) => setState(() => _replace = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pasteCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '粘贴二维码文本',
            hintText: '可一次粘贴多段（每行一段），或粘贴完整 JSON',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _ingestPasted(_pasteCtrl.text),
          icon: const Icon(Icons.download),
          label: const Text('导入粘贴内容'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            final text = data?.text;
            if (text == null || text.trim().isEmpty) {
              SmartDialog.showToast('剪贴板为空');
              return;
            }
            _pasteCtrl.text = text;
            _ingestPasted(text);
          },
          icon: const Icon(Icons.content_paste),
          label: const Text('从剪贴板导入'),
        ),
        if (total != null) ...[
          const SizedBox(height: 16),
          Text(
            '分段进度：${_received.length} / $total',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total == 0 ? 0 : _received.length / total,
          ),
          TextButton(
            onPressed: () => setState(() {
              _received.clear();
              _expectedTotal = null;
            }),
            child: const Text('清空已收分段'),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          '用法：在导出端显示二维码或复制文本，在本机粘贴导入。'
          '文件导入仍可在「本地数据导入导出」中使用。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
