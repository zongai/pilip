import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/utils/local_lan_sync.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class LocalLanSyncPage extends StatefulWidget {
  const LocalLanSyncPage({super.key});

  @override
  State<LocalLanSyncPage> createState() => _LocalLanSyncPageState();
}

class _LocalLanSyncPageState extends State<LocalLanSyncPage> {
  final _host = LocalLanSyncHost.instance;
  bool _hosting = false;
  bool _scanning = false;
  bool _busy = false;
  bool _autoSync = Pref.enableLanAutoSync;
  List<LanPeer> _peers = [];
  List<String> _localIps = [];
  String? _pin;
  late Set<String> _cats;
  final _ipCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cats = Pref.lanSyncCategories.toSet();
    _refreshLocalIps();
    _hosting = _host.isRunning;
    _pin = _host.pin;
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshLocalIps() async {
    final ips = await LocalLanSync.localIPv4s();
    if (mounted) setState(() => _localIps = ips);
  }

  Future<void> _toggleHost(bool on) async {
    try {
      if (on) {
        await _host.start();
        setState(() {
          _hosting = true;
          _pin = _host.pin;
        });
        await _refreshLocalIps();
        SmartDialog.showToast('已开启，PIN：${_host.pin}。若对方扫不到，请在系统防火墙允许本应用的专用网络访问');
      } else {
        await _host.stop();
        setState(() {
          _hosting = false;
          _pin = null;
        });
        SmartDialog.showToast('已停止共享');
      }
    } catch (e) {
      SmartDialog.showToast('操作失败：$e');
      setState(() {
        _hosting = _host.isRunning;
        _pin = _host.pin;
      });
    }
  }


  Future<void> _connectManual() async {
    final raw = _ipCtrl.text.trim();
    if (raw.isEmpty) {
      SmartDialog.showToast('请输入对方 IP');
      return;
    }
    var host = raw;
    var port = LocalLanSync.httpPort;
    if (raw.contains(':')) {
      final i = raw.lastIndexOf(':');
      host = raw.substring(0, i);
      port = int.tryParse(raw.substring(i + 1)) ?? LocalLanSync.httpPort;
    }
    final mine = await LocalLanSync.localIPv4s();
    if (mine.contains(host)) {
      SmartDialog.showToast('这是本机地址，请填写对方「本机」列表中的 IP');
      return;
    }
    setState(() => _busy = true);
    SmartDialog.showLoading(msg: '连接 $host:$port …');
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.idleTimeout = const Duration(seconds: 12);
      final uri = Uri.parse('http://$host:$port/info');
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode != 200) {
        SmartDialog.showToast('连接失败：HTTP ${res.statusCode}');
        return;
      }
      final json = jsonDecode(body);
      if (json is! Map) {
        SmartDialog.showToast('无效响应');
        return;
      }
      final peer = LanPeer(
        name: '${json['name'] ?? host}',
        host: host,
        port: port,
        deviceId: '${json['deviceId'] ?? host}',
      );
      if (mounted) {
        setState(() {
          _peers = [peer, ..._peers.where((e) => e.deviceId != peer.deviceId)];
        });
      }
      final addrs = json['addresses'];
      final extra = addrs is List && addrs.isNotEmpty
          ? '（对方：${addrs.take(3).join(", ")}）'
          : '';
      SmartDialog.showToast('已连接 ${peer.name}$extra');
    } on SocketException catch (e) {
      final timedOut = e.message.contains('timed out') ||
          e.message.contains('Timeout') ||
          (e.osError?.errorCode == 110);
      SmartDialog.showToast(
        timedOut
            ? '连接超时 $host:$port。请确认对方已开同步源、IP 为对方 192.168.x（非 VPN），且防火墙放行'
            : '连接失败：$e',
      );
    } on TimeoutException {
      SmartDialog.showToast('连接超时。请使用对方本机显示的 192.168.x 地址，并检查防火墙');
    } catch (e) {
      SmartDialog.showToast('连接失败：$e');
    } finally {
      SmartDialog.dismiss();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _peers = [];
    });
    try {
      final list = await LocalLanSyncClient.discover();
      if (mounted) {
        setState(() => _peers = list);
        if (list.isEmpty) {
          SmartDialog.showToast(
            '未发现附近设备。请确认对方已开启同步、同一 WiFi，并检查防火墙',
            displayTime: const Duration(seconds: 4),
          );
        }
      }
    } catch (e) {
      SmartDialog.showToast('扫描失败：$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<String?> _askPin(LanPeer peer, {String title = '输入 PIN'}) async {
    final saved = peer.savedPin;
    if (saved != null && peer.isTrusted) {
      // 已配对：直接用保存的 PIN，也可让用户改
      return saved;
    }
    final pinCtrl = TextEditingController(text: saved ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '对方 PIN',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final pin = pinCtrl.text.trim();
    pinCtrl.dispose();
    if (ok != true || pin.isEmpty) return null;
    return pin;
  }

  Future<void> _pull(LanPeer peer) async {
    final pin = await _askPin(peer, title: '从「${peer.name}」拉取合并');
    if (pin == null) return;
    setState(() => _busy = true);
    SmartDialog.showLoading(msg: '拉取中…');
    try {
      final ok = await LocalLanSyncClient.pullAndMerge(
        peer: peer,
        pin: pin,
        categories: _cats.toList(),
        remember: true,
      );
      if (ok) {
        SmartDialog.showToast('已合并并记住该设备');
        setState(() {});
      }
    } finally {
      SmartDialog.dismiss();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push(LanPeer peer) async {
    final pin = await _askPin(peer, title: '推送到「${peer.name}」');
    if (pin == null) return;
    setState(() => _busy = true);
    SmartDialog.showLoading(msg: '推送中…');
    try {
      await LocalLanSyncClient.pushToPeer(
        peer: peer,
        pin: pin,
        categories: _cats.toList(),
        remember: true,
      );
      setState(() {});
    } finally {
      SmartDialog.dismiss();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveCats() {
    Pref.lanSyncCategories = _cats.toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trusted = Pref.lanTrustedPeers;
    return Scaffold(
      appBar: AppBar(title: const Text('局域网同步')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '同一 Wi‑Fi 下发现设备，PIN 确认后同步。已配对设备可少输 PIN；可勾选同步类型。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启动时自动同步已配对设备'),
            subtitle: const Text('进入应用后扫描并静默合并（需对方开启同步源）'),
            value: _autoSync,
            onChanged: (v) {
              Pref.enableLanAutoSync = v;
              setState(() => _autoSync = v);
            },
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('作为同步源'),
                    subtitle: const Text('开启后可被发现，并接收对方推送'),
                    value: _hosting,
                    onChanged: _busy ? null : _toggleHost,
                  ),
                  if (_hosting) ...[
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('本机 PIN'),
                      subtitle: Text(
                        _pin ?? '----',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          letterSpacing: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: '刷新 PIN',
                        icon: const Icon(Icons.refresh),
                        onPressed: () async {
                          await _host.stop();
                          await _host.start();
                          setState(() => _pin = _host.pin);
                        },
                      ),
                    ),
                    if (_localIps.isNotEmpty) ...[
                      Text(
                        '请让对方填写第一项（优先 192.168.x，勿用 VPN/虚拟网卡）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _localIps
                            .map((e) => '$e:${LocalLanSync.httpPort}')
                            .join('
'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('同步内容', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              for (final e in LocalLanSync.categoryLabels.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _cats.contains(e.key),
                  onSelected: (sel) {
                    setState(() {
                      if (sel) {
                        _cats.add(e.key);
                      } else {
                        _cats.remove(e.key);
                      }
                      _saveCats();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (trusted.isNotEmpty) ...[
            Text('已配对设备', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            ...trusted.map((t) {
              final id = '${t['deviceId']}';
              final name = '${t['name'] ?? id}';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(name),
                subtitle: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: '取消配对',
                  icon: const Icon(Icons.link_off),
                  onPressed: () {
                    Pref.removeLanTrustedPeer(id);
                    setState(() {});
                  },
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text('附近设备', style: theme.textTheme.titleMedium),
              ),
              FilledButton.tonalIcon(
                onPressed: _scanning || _busy ? null : _scan,
                icon: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.radar),
                label: Text(_scanning ? '扫描中' : '扫描'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: '手动 IP',
                    hintText: '例如 192.168.1.8',
                  ),
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _connectManual(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _connectManual,
                child: const Text('连接'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  _scanning
                      ? '正在搜索（广播 + 网段探测）…'
                      : '点击扫描。对方须先开启「允许同步」且同一 WiFi',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            )
          else
            ..._peers.map(
              (p) => Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          p.isTrusted ? Icons.verified : Icons.phone_android,
                        ),
                        title: Text(
                          p.isTrusted ? '${p.name}（已配对）' : p.name,
                        ),
                        subtitle: Text('${p.host}:${p.port}'),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : () => _push(p),
                            child: const Text('推送到对方'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _busy ? null : () => _pull(p),
                            child: Text(p.isTrusted ? '拉取合并' : '同步'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            '说明\n'
            '· 拉取：合并对方数据到本机；推送：把本机数据合并到对方\n'
            '· 成功后自动配对，下次可少输 PIN；启动自动同步仅对已配对设备\n'
            '· 仅在可信设备与同一 Wi‑Fi 下使用',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
