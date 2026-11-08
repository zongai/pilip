import 'dart:async';
import 'dart:io' show Platform;

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
  Timer? _cycleTimer;
  bool _autoCycle = true;
  static const _cycleInterval = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _rebuildChunks();
    _tab.addListener(_onTabChanged);
    _startCycleIfNeeded();
  }

  void _onTabChanged() {
    if (_tab.index == 1) {
      _stopCycle();
      _startScanner();
    } else {
      _stopScanner();
      _startCycleIfNeeded();
    }
  }

  void _rebuildChunks() {
    setState(() {
      _chunks = LocalListIo.buildQrChunks();
      _index = 0;
    });
    _startCycleIfNeeded();
  }

  void _startCycleIfNeeded() {
    _stopCycle();
    if (!_autoCycle || _chunks.length <= 1 || _tab.index != 0) return;
    _cycleTimer = Timer.periodic(_cycleInterval, (_) {
      if (!mounted || _chunks.isEmpty) return;
      setState(() {
        _index = (_index + 1) % _chunks.length;
      });
    });
  }

  void _stopCycle() {
    _cycleTimer?.cancel();
    _cycleTimer = null;
  }

  CameraFacing _facing =
      Platform.isWindows || Platform.isMacOS || Platform.isLinux
          ? CameraFacing.front
          : CameraFacing.back;

  Future<void> _startScanner() async {
    if (_scanner != null) return;
    try {
      // Windows：首次使用相机会走系统隐私授权；桌面默认前置摄像头
      final controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: _facing,
        autoStart: true,
      );
      await controller.start();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _scanner = controller;
      setState(() => _scanning = true);
    } catch (e) {
      await _scanner?.dispose();
      _scanner = null;
      if (mounted) setState(() => _scanning = false);
      final tip = Platform.isWindows
          ? '无法打开摄像头。请到「设置 → 隐私和安全性 → 相机」中允许桌面应用访问相机，并确认本机有可用摄像头。\n详情: $e'
          : '无法启动相机: $e';
      SmartDialog.showToast(tip, displayTime: const Duration(seconds: 5));
    }
  }

  Future<void> _stopScanner() async {
    final c = _scanner;
    _scanner = null;
    try {
      await c?.stop();
    } catch (_) {}
    await c?.dispose();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _switchCamera() async {
    await _stopScanner();
    setState(() {
      _facing = _facing == CameraFacing.back
          ? CameraFacing.front
          : CameraFacing.back;
    });
    await _startScanner();
  }

  @override
  void dispose() {
    _stopCycle();
    _tab.removeListener(_onTabChanged);
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
              onPressed: _chunks.length > 1
                  ? () {
                      setState(() {
                        _index = (_index - 1 + _chunks.length) % _chunks.length;
                      });
                    }
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${_index + 1} / ${_chunks.length}'
                '${_autoCycle && _chunks.length > 1 ? ' · 自动循环' : ''}',
              ),
            ),
            IconButton.filledTonal(
              onPressed: _chunks.length > 1
                  ? () {
                      setState(() {
                        _index = (_index + 1) % _chunks.length;
                      });
                    }
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (_chunks.length > 1) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动循环显示'),
            subtitle: const Text('约每 2 秒切换下一段，便于对方连续扫描'),
            value: _autoCycle,
            onChanged: (v) {
              setState(() => _autoCycle = v);
              if (v) {
                _startCycleIfNeeded();
              } else {
                _stopCycle();
              }
            },
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '数据较多时会分成多段，开启自动循环后对方可持续扫描。',
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
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off_outlined, size: 48),
                        const SizedBox(height: 12),
                        const Text('相机未就绪'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _startScanner,
                          icon: const Icon(Icons.photo_camera),
                          label: const Text('启动扫描'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          Platform.isWindows
                              ? 'Windows 需在「设置 → 隐私和安全性 → 相机」中允许桌面应用访问相机；首次打开时系统可能会弹出授权提示。'
                              : '请允许应用使用摄像头以扫描二维码。',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _scanner,
                      onDetect: _onDetect,
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        tooltip: '切换摄像头',
                        onPressed: _switchCamera,
                        child: const Icon(Icons.cameraswitch_outlined),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
