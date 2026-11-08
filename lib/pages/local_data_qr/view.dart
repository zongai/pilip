import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

/// 本地数据二维码同步：导出展示二维码；导入用 universal_barcode_scanner（含 Windows 摄像头）
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
  ScannerController? _scannerCtrl;
  Timer? _cycleTimer;
  bool _autoCycle = true;
  static const _cycleInterval = Duration(milliseconds: 1000);
  String? _cameraError;

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

  void _startScanner() {
    setState(() {
      _cameraError = null;
      _scanning = true;
    });
  }

  void _stopScanner() {
    try {
      _scannerCtrl?.pauseScanning();
    } catch (_) {}
    _scannerCtrl = null;
    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _stopCycle();
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _scannerCtrl = null;
    super.dispose();
  }

  Future<void> _ingestScanText(String text) async {
    text = text.trim();
    if (text.isEmpty || _handling) return;

    // 完整 JSON
    if (!text.startsWith('${LocalListIo.qrPrefix}|')) {
      if (text.startsWith('{')) {
        _handling = true;
        try {
          _stopScanner();
          final ok = await LocalListIo.importFromQrTexts(
            [text],
            replace: _replace,
          );
          if (ok && mounted) {
            setState(() {
              _received.clear();
              _expectedTotal = null;
            });
            SmartDialog.showToast('导入完成');
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
        _stopScanner();
        final ok = await LocalListIo.importFromQrTexts(
          _received.values.toList(),
          replace: _replace,
        );
        if (ok && mounted) {
          setState(() {
            _received.clear();
            _expectedTotal = null;
          });
          SmartDialog.showToast('同步完成，共 $tot 段');
        }
      } finally {
        _handling = false;
      }
    }
  }

  Future<void> _scanFromImageFile() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.image);
      if (f == null) return;
      final bytes = await f.xFile.readAsBytes();
      if (bytes.isEmpty) {
        SmartDialog.showToast('无法读取图片');
        return;
      }
      final codes = await UniversalBarcodeScanner.scanImage(
        bytes,
        scanFormat: ScanFormat.onlyQrCode,
      );
      if (codes.isEmpty) {
        SmartDialog.showToast('图片中未识别到同步二维码');
        return;
      }
      for (final c in codes) {
        final text = c.text.trim();
        if (text.isEmpty) continue;
        await _ingestScanText(text);
        if (_handling) break;
      }
    } on ScannerException catch (e) {
      SmartDialog.showToast('读图失败: ${e.message ?? e.code}');
    } catch (e) {
      SmartDialog.showToast('读图失败: $e');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      SmartDialog.showToast('剪贴板为空');
      return;
    }
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    for (final line in lines) {
      await _ingestScanText(line);
      if (_handling) break;
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
          '第 ${_index + 1} / ${_chunks.length} 段'
          '${_autoCycle && _chunks.length > 1 ? ' · 自动循环' : ''}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: SizedBox(
              width: 360,
              height: 360,
              child: PrettyQrView.data(
                data: chunk,
                decoration: const PrettyQrDecoration(
                  shape: PrettyQrSmoothSymbol(roundFactor: 0),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_chunks.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _index = (_index - 1 + _chunks.length) % _chunks.length;
                  });
                },
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _autoCycle = !_autoCycle);
                  _startCycleIfNeeded();
                },
                child: Text(_autoCycle ? '暂停循环' : '自动循环'),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _index = (_index + 1) % _chunks.length;
                  });
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          '对端用「扫描导入」或「从图片识别」依次读取；段数越少同步越快。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildImport(ThemeData theme) {
    final total = _expectedTotal ?? 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('导入时覆盖已有数据'),
                subtitle: const Text('关闭则为合并'),
                value: _replace,
                onChanged: (v) => setState(() => _replace = v),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _scanFromImageFile,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('从图片识别'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.paste),
                    label: const Text('粘贴文本'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _scanning ? _stopScanner : _startScanner,
                    icon: Icon(
                      _scanning ? Icons.videocam_off : Icons.photo_camera,
                    ),
                    label: Text(_scanning ? '关闭摄像头' : '打开摄像头'),
                  ),
                ],
              ),
              if (_cameraError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _cameraError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (total > 0) ...[
                const SizedBox(height: 8),
                Text('进度：${_received.length}/$total'),
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
            ],
          ),
        ),
        Expanded(
          child: _scanning
              ? UniversalBarcodeScanner(
                  onCreated: (ctrl) {
                    _scannerCtrl = ctrl;
                  },
                  continuous: true,
                  scanDelay: const Duration(milliseconds: 400),
                  scanWindow: ScanWindow.square,
                  cameraFace: Platform.isWindows ||
                          Platform.isMacOS ||
                          Platform.isLinux
                      ? CameraFace.front
                      : CameraFace.back,
                  scanFormat: ScanFormat.onlyQrCode,
                  buttons: const {
                    ScannerButton.torch,
                    ScannerButton.switchCamera,
                  },
                  onScanned: (code) {
                    unawaited(_ingestScanText(code));
                  },
                  onError: (e) {
                    if (!mounted) return;
                    final msg = e.message ?? '${e.code}';
                    setState(() {
                      _cameraError = msg;
                      _scanning = false;
                    });
                    SmartDialog.showToast(
                      '摄像头: $msg',
                      displayTime: const Duration(seconds: 4),
                    );
                  },
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '打开摄像头对准导出端二维码；收齐全部段后自动导入。\n'
                      '也可用「从图片识别」选截图，或「粘贴文本」。\n'
                      'Windows 需已安装 WebView2（Win11 / 新版 Edge 通常自带）。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
