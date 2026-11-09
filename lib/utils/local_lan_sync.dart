import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 局域网自动发现 + 用户确认后的本地数据同步（已看/历史、关注、黑名单、播单等）
abstract final class LocalLanSync {
  static const int udpPort = 37218;
  static const int httpPort = 37219;
  static const String magicProbe = 'PILIP_SYNC_PROBE';
  static const String magicAnnounce = 'PILIP_SYNC_ANNOUNCE';
  static const String serviceName = 'PiliPlus';

  static String? _deviceName;
  static String? _deviceId;

  static Future<String> deviceName() async {
    if (_deviceName != null) return _deviceName!;
    try {
      _deviceName = Platform.localHostname;
    } catch (_) {
      _deviceName = 'PiliPlus';
    }
    return _deviceName!;
  }

  static String deviceId() {
    if (_deviceId != null) return _deviceId!;
    // 进程内稳定即可；配对不持久化到此阶段
    _deviceId =
        '${Platform.operatingSystem}-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    return _deviceId!;
  }

  static Future<List<String>> localIPv4s() async {
    final out = <String>[];
    try {
      for (final ni in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final a in ni.addresses) {
          if (!a.isLoopback) out.add(a.address);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('localIPv4s: $e');
    }
    return out;
  }
}

class LanPeer {
  const LanPeer({
    required this.name,
    required this.host,
    required this.port,
    required this.deviceId,
  });

  final String name;
  final String host;
  final int port;
  final String deviceId;

  String get endpoint => 'http://$host:$port';

  @override
  bool operator ==(Object other) =>
      other is LanPeer && other.deviceId == deviceId && other.host == host;

  @override
  int get hashCode => Object.hash(deviceId, host);
}

/// 本机作为同步源：UDP 可被发现 + HTTP 提供快照
class LocalLanSyncHost {
  LocalLanSyncHost._();
  static final LocalLanSyncHost instance = LocalLanSyncHost._();

  HttpServer? _http;
  RawDatagramSocket? _udp;
  StreamSubscription? _udpSub;
  String? pin;
  bool get isRunning => _http != null;

  final _status = StreamController<String>.broadcast();
  Stream<String> get status$ => _status.stream;

  Future<void> start() async {
    if (isRunning) return;
    pin = (1000 + Random().nextInt(9000)).toString();
    final name = await LocalLanSync.deviceName();
    final id = LocalLanSync.deviceId();

    _http = await HttpServer.bind(InternetAddress.anyIPv4, LocalLanSync.httpPort);
    _http!.listen((req) async {
      try {
        await _handleHttp(req, name, id);
      } catch (e) {
        if (kDebugMode) debugPrint('lan host http: $e');
        try {
          req.response.statusCode = 500;
          await req.response.close();
        } catch (_) {}
      }
    });

    _udp = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      LocalLanSync.udpPort,
      reuseAddress: true,
    );
    try {
      _udp!.broadcastEnabled = true;
    } catch (_) {}
    _udpSub = _udp!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = _udp!.receive();
      if (dg == null) return;
      final msg = utf8.decode(dg.data, allowMalformed: true);
      if (msg.startsWith(LocalLanSync.magicProbe)) {
        final announce = jsonEncode({
          'name': name,
          'port': LocalLanSync.httpPort,
          'deviceId': id,
          'pinRequired': true,
        });
        final bytes = utf8.encode('${LocalLanSync.magicAnnounce}|$announce');
        try {
          _udp!.send(bytes, dg.address, dg.port);
          // 也回发到对方常见端口，便于对称发现
          _udp!.send(bytes, dg.address, LocalLanSync.udpPort);
        } catch (_) {}
      }
    });

    _status.add('running');
  }

  Future<void> stop() async {
    await _udpSub?.cancel();
    _udpSub = null;
    _udp?.close();
    _udp = null;
    await _http?.close(force: true);
    _http = null;
    pin = null;
    _status.add('stopped');
  }

  Future<void> _handleHttp(HttpRequest req, String name, String id) async {
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    final path = req.uri.path;

    if (req.method == 'OPTIONS') {
      res.statusCode = 204;
      await res.close();
      return;
    }

    if (path == '/info' && req.method == 'GET') {
      final payload = LocalListIo.buildFullPayload();
      final counts = payload['counts'] ?? {};
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'name': name,
        'deviceId': id,
        'service': LocalLanSync.serviceName,
        'counts': counts,
        'exportedAt': payload['exportedAt'],
      }));
      await res.close();
      return;
    }

    if (path == '/snapshot' && req.method == 'GET') {
      final qPin = req.uri.queryParameters['pin'] ?? '';
      if (pin == null || qPin != pin) {
        res.statusCode = 403;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'error': 'invalid_pin'}));
        await res.close();
        return;
      }
      final payload = LocalListIo.buildFullPayload();
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(payload));
      await res.close();
      return;
    }

    res.statusCode = 404;
    await res.close();
  }
}

/// 扫描局域网并拉取合并
class LocalLanSyncClient {
  LocalLanSyncClient._();
  static final LocalLanSyncClient instance = LocalLanSyncClient._();

  /// 广播探测，收集附近主机（默认约 2.5s）
  static Future<List<LanPeer>> discover({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final found = <String, LanPeer>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      final probe = utf8.encode(LocalLanSync.magicProbe);
      final targets = <InternetAddress>[
        InternetAddress('255.255.255.255'),
      ];
      // 子网广播
      for (final ip in await LocalLanSync.localIPv4s()) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
        }
      }

      void sendProbes() {
        for (final t in targets) {
          try {
            sock!.send(probe, t, LocalLanSync.udpPort);
          } catch (_) {}
        }
      }

      sendProbes();
      final timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
        sendProbes();
      });

      final sub = sock.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = sock!.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        if (!msg.startsWith('${LocalLanSync.magicAnnounce}|')) return;
        try {
          final json = jsonDecode(msg.substring(LocalLanSync.magicAnnounce.length + 1));
          if (json is! Map) return;
          final port = json['port'];
          final deviceId = '${json['deviceId'] ?? ''}';
          final name = '${json['name'] ?? 'PiliPlus'}';
          final p = port is int ? port : int.tryParse('$port') ?? LocalLanSync.httpPort;
          if (deviceId.isEmpty) return;
          // 跳过本机
          if (deviceId == LocalLanSync.deviceId()) return;
          final peer = LanPeer(
            name: name,
            host: dg.address.address,
            port: p,
            deviceId: deviceId,
          );
          found[deviceId] = peer;
        } catch (_) {}
      });

      await Future<void>.delayed(timeout);
      timer.cancel();
      await sub.cancel();
    } catch (e) {
      if (kDebugMode) debugPrint('discover: $e');
    } finally {
      sock?.close();
    }
    return found.values.toList();
  }

  /// 拉取对方快照并合并到本机（默认 merge，不覆盖删除）
  static Future<bool> pullAndMerge({
    required LanPeer peer,
    required String pin,
    bool replace = false,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    client.idleTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(
        '${peer.endpoint}/snapshot?pin=${Uri.encodeQueryComponent(pin)}',
      );
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 403) {
        SmartDialog.showToast('PIN 错误');
        return false;
      }
      if (res.statusCode != 200) {
        SmartDialog.showToast('同步失败：HTTP ${res.statusCode}');
        return false;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        SmartDialog.showToast('数据格式无效');
        return false;
      }
      await LocalListIo.applyDecodedMap(
        Map<String, dynamic>.from(decoded),
        replace: replace,
      );
      return true;
    } catch (e) {
      SmartDialog.showToast('同步失败：$e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> fetchInfo(LanPeer peer) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(Uri.parse('${peer.endpoint}/info'));
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    return null;
  }
}
