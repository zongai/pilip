import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// 本地数据二维码同步：导出展示二维码，导入扫描二维码
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
  final _received = <int, String>{};
  int? _expectedTotal;
  bool _replace = false;
  bool _scanning = false;
  bool _handling = false;
  MobileScannerController? _scanner;

  @override
  void initState() {
    super.initState();
    _rebuildChunks();
    _tab.addListener(() {
      if (_tab.index == 1) {
        _startScanner();
      } else {
        _stopScanner();
      }
    });
  }

  void _rebuildChunks() {
    setState(() {
      _chunks = LocalListIo.buildQrChunks();
      _index = 0;
    });
  }

  Future<void> _startScanner() async {
    if (_scanner != null) return;
    try {
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );
      setState(() => _scanning = true);
    } catch (e) {
      SmartDialog.showToast('无法启动相机: $e');
      setState(() => _scanning = false);
    }
  }

  Future<void> _stopScanner() async {
    final c = _scanner;
    _scanner = null;
    await c?.dispose();
    if (mounted) setState(() => _scanning = false);
  }

  @override
  void dispose() {
    _tab.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes
        .map((e) => e.rawValue)
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (raw.isEmpty) return;

    for (final text in raw) {
      await _ingestScanText(text);
    }
  }

  Future<void> _ingestScanText(String text) async {
    if (_handling) return;

    // 完整 JSON
    if (!text.startsWith('${LocalListIo.qrPrefix}|')) {
      if (text.startsWith('{')) {
        _handling = true;
        try {
          final ok = await LocalListIo.importFromQrTexts(
            [text],
            replace: _replace,
          );
          if (ok && mounted) {
            setState(() {
              _received.clear();
              _expectedTotal = null;
            });
          }
        } finally {
          _handling = false;
        }
      }
      return;
    }

    final segs = text.split('|');
    if (segs.length < 4) return;
    final idx = int.tryParse(segs[1]);
    final tot = int.tryParse(segs[2]);
    if (idx == null || tot == null) return;

    if (_received.containsKey(idx)) return;

    setState(() {
      _expectedTotal = tot;
      _received[idx] = text;
    });
    SmartDialog.showToast('已扫描 ${_received.length}/$tot');

    if (_received.length >= tot) {
      _handling = true;
      try {
        final ok = await LocalListIo.importFromQrTexts(
          _received.values.toList(),
          replace: _replace,
        );
        if (ok && mounted) {
          setState(() {
            _received.clear();
            _expectedTotal = null;
          });
        }
      } finally {
        _handling = false;
      }
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
            Tab(text: '扫描导入'),
          ],
        ),
        actions: [
          if (_tab.index == 0)
            IconButton(
              tooltip: '刷新',
              onPressed: _rebuildChunks,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildExport(theme),
          _buildImport(theme),
        ],
      ),
    );
  }

  Widget _buildExport(ThemeData theme) {
    if (_chunks.isEmpty) {
      return const Center(child: Text('无数据可导出'));
    }
    final chunk = _chunks[_index.clamp(0, _chunks.length - 1)];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '在另一台设备打开「扫描导入」，对准此二维码',
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                ),
              ],
            ),
            child: SizedBox(
              width: 280,
              height: 280,
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
              onPressed:
                  _index > 0 ? () => setState(() => _index--) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('${_index + 1} / ${_chunks.length}'),
            ),
            IconButton.filledTonal(
              onPressed: _index < _chunks.length - 1
                  ? () => setState(() => _index++)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '数据较多时会分成多段，请按顺序让对方扫完每一段。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildImport(ThemeData theme) {
    final total = _expectedTotal;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('覆盖导入'),
          subtitle: const Text('关闭则与现有数据合并'),
          value: _replace,
          onChanged: (v) => setState(() => _replace = v),
        ),
        if (total != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('分段进度：${_received.length} / $total'),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : _received.length / total,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _received.clear();
                      _expectedTotal = null;
                    }),
                    child: const Text('清空进度'),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _scanner == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('相机未就绪'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _startScanner,
                        child: const Text('启动扫描'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '桌面端若无摄像头，请使用手机扫描另一台设备的导出二维码',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                )
              : ClipRect(
                  child: MobileScanner(
                    controller: _scanner,
                    onDetect: _onDetect,
                  ),
                ),
        ),
      ],
    );
  }
}
