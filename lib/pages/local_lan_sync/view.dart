import 'package:PiliPlus/utils/local_lan_sync.dart';
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
  bool _syncing = false;
  List<LanPeer> _peers = [];
  List<String> _localIps = [];
  String? _pin;

  @override
  void initState() {
    super.initState();
    _refreshLocalIps();
    _hosting = _host.isRunning;
    _pin = _host.pin;
  }

  @override
  void dispose() {
    // 离开页面不强制关 host，便于后台继续被发现；用户可手动停止
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
        SmartDialog.showToast('已开启，PIN：${_host.pin}');
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
          SmartDialog.showToast('未发现附近设备，请确认对方已开启共享');
        }
      }
    } catch (e) {
      SmartDialog.showToast('扫描失败：$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _syncFrom(LanPeer peer) async {
    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('从「${peer.name}」同步'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${peer.host}:${peer.port}\n将合并对方的本地数据（已看/历史、关注、黑名单、播单等），不会清空本机已有内容。',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('合并同步'),
          ),
        ],
      ),
    );
    final pin = pinCtrl.text.trim();
    pinCtrl.dispose();
    if (ok != true || pin.isEmpty) return;

    setState(() => _syncing = true);
    SmartDialog.showLoading(msg: '同步中…');
    try {
      final success = await LocalLanSyncClient.pullAndMerge(
        peer: peer,
        pin: pin,
        replace: false,
      );
      if (success) {
        SmartDialog.showToast('同步完成');
      }
    } finally {
      SmartDialog.dismiss();
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('局域网同步')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '同一 Wi‑Fi 下自动发现附近设备，输入 PIN 后合并同步本地数据（无需登录、不经过公网）。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('作为同步源'),
                    subtitle: const Text('开启后可被附近设备发现并拉取本机数据'),
                    value: _hosting,
                    onChanged: _syncing ? null : _toggleHost,
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
                    if (_localIps.isNotEmpty)
                      Text(
                        '本机地址：${_localIps.map((e) => '$e:${LocalLanSync.httpPort}').join('， ')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '附近设备',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _scanning || _syncing ? null : _scan,
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
          if (_peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _scanning ? '正在搜索…' : '点击扫描发现附近已开启共享的设备',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            )
          else
            ..._peers.map(
              (p) => Card(
                child: ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: Text(p.name),
                  subtitle: Text('${p.host}:${p.port}'),
                  trailing: FilledButton(
                    onPressed: _syncing ? null : () => _syncFrom(p),
                    child: const Text('同步'),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            '说明\n'
            '· 同步内容：本地关注、黑名单、播单、历史/已看、稍后再看、合集、搜索历史等\n'
            '· 默认合并：只增不覆盖删除；进度取较新/较大\n'
            '· 请仅在可信设备间使用，PIN 勿告知他人',
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
