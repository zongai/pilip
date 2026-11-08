import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zxing2/qrcode.dart';

/// 本地数据二维码同步：导出展示二维码，导入扫描/读图/粘贴
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
  /// 加快轮播：约 1 秒一段
  static const _cycleInterval = Duration(milliseconds: 1000);
  final bool _isDesktop =
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  String? _cameraError;

  CameraFacing _facing = Platform.isWindows || Platform.isMacOS || Platform.isLinux
      ? CameraFacing.front
      : CameraFacing.back;

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
      // 桌面端相机插件常不可用，不自动强开；用户可点「尝试打开摄像头」
      if (!_isDesktop) {
        _startScanner();
      }
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

  Future<void> _startScanner() async {
    if (_scanner != null) return;
    setState(() => _cameraError = null);
    try {
      final controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.unrestricted,
        facing: _facing,
        autoStart: false,
      );
      await controller.start();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _scanner = controller;
        _scanning = true;
        _cameraError = null;
      });
    } on MissingPluginException catch (e) {
      await _disposeScannerQuiet();
      final msg = Platform.isWindows
          ? '当前 Windows 构建未接入摄像头插件，请改用「从图片识别」或「粘贴文本」。'
          : '本平台无相机插件实现，请使用图片识别或粘贴。';
      if (mounted) {
        setState(() {
          _scanning = false;
          _cameraError = msg;
        });
      }
      SmartDialog.showToast('$msg\n($e)', displayTime: const Duration(seconds: 4));
    } catch (e) {
      await _disposeScannerQuiet();
      final tip = Platform.isWindows
          ? '无法打开摄像头。请到「设置 → 隐私和安全性 → 相机」允许桌面应用访问相机。\n也可使用「从图片识别」。'
          : '无法启动相机: $e';
      if (mounted) {
        setState(() {
          _scanning = false;
          _cameraError = tip;
        });
      }
      SmartDialog.showToast(tip, displayTime: const Duration(seconds: 4));
    }
  }

  Future<void> _disposeScannerQuiet() async {
    final c = _scanner;
    _scanner = null;
    try {
      await c?.stop();
    } catch (_) {}
    try {
      await c?.dispose();
    } catch (_) {}
  }

  Future<void> _stopScanner() async {
    await _disposeScannerQuiet();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _switchCamera() async {
    await _stopScanner();
    setState(() {
      _facing =
          _facing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
    });
    await _startScanner();
  }

  @override
  void dispose() {
    _stopCycle();
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    unawaited(_disposeScannerQuiet());
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
      if (_handling) break;
    }
  }

  Future<void> _ingestScanText(String text) async {
    if (_handling) return;

    // 完整 JSON
    if (!text.startsWith('${LocalListIo.qrPrefix}|')) {
      if (text.startsWith('{')) {
        _handling = true;
        try {
          await _stopScanner();
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

    // 收齐全部段后立刻停止扫描并导入
    if (_received.length >= tot) {
      _handling = true;
      try {
        await _stopScanner();
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

  /// 从图片文件识别二维码（桌面主路径，不依赖相机插件）
  Future<void> _scanFromImageFile() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.image);
      if (f == null) return;
      final bytes = await f.xFile.readAsBytes();
      if (bytes.isEmpty) {
        SmartDialog.showToast('无法读取图片');
        return;
      }
      final text = _decodeQrFromImageBytes(bytes);
      if (text == null || text.isEmpty) {
        SmartDialog.showToast('图片中未识别到同步二维码');
        return;
      }
      await _ingestScanText(text);
    } catch (e) {
      SmartDialog.showToast('读图失败: $e');
    }
  }

  static String? _decodeQrFromImageBytes(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      // 过大图缩小，加快识别
      var image = decoded;
      const maxSide = 1200;
      if (image.width > maxSide || image.height > maxSide) {
        image = img.copyResize(
          image,
          width: image.width >= image.height ? maxSide : null,
          height: image.height > image.width ? maxSide : null,
        );
      }
      final rgba = image.convert(numChannels: 4);
      final pixels = rgba.getBytes(order: img.ChannelOrder.rgba);
      // zxing2 RGBLuminanceSource 期望每像素 int（可用打包 RGB）
      final rgb = Int32List(rgba.width * rgba.height);
      for (var i = 0; i < rgb.length; i++) {
        final o = i * 4;
        final r = pixels[o];
        final g = pixels[o + 1];
        final b = pixels[o + 2];
        rgb[i] = (r << 16) | (g << 8) | b;
      }
      final source = RGBLuminanceSource(rgba.width, rgba.height, rgb);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final result = QRCodeReader().decode(bitmap);
      return result.text;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      SmartDialog.showToast('剪贴板为空');
      return;
    }
    // 支持多段用换行拼接
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
                  // mobile_scanner 官方不支持 Windows/Linux，避免点了报 MissingPluginException
                  if (!_isDesktop || Platform.isMacOS)
                    OutlinedButton.icon(
                      onPressed: _scanning ? _stopScanner : _startScanner,
                      icon: Icon(
                        _scanning ? Icons.videocam_off : Icons.photo_camera,
                      ),
                      label: Text(_scanning ? '关闭摄像头' : '打开摄像头'),
                    ),
                ],
              ),
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
          child: _scanner == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      Platform.isWindows || Platform.isLinux
                          ? 'Windows 不支持摄像头扫码。\n请对导出端二维码截图，点「从图片识别」选图；或使用「粘贴文本」。\n收齐全部段后会自动导入。'
                          : '将摄像头对准导出端二维码；收齐全部段后会自动停止并导入。也可从图片识别。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
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
