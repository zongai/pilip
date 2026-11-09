import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:PiliPlus/utils/local_list_io.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 局域网自动发现 + PIN/已配对 同步本地数据
abstract final class LocalLanSync {
  static const int udpPort = 37218;
  static const int httpPort = 37219;
  static const String magicProbe = 'PILIP_SYNC_PROBE';
  static const String magicAnnounce = 'PILIP_SYNC_ANNOUNCE';
  static const String serviceName = 'PiliPlus';

  static const Map<String, String> categoryLabels = {
    'follows': '本地关注',
    'blacklist': '黑名单',
    'playlists': '播单(旧)',
    'videoPlaylists': '本地播单',
    'seasons': '合集',
    'history': '历史/已看',
    'later': '稍后再看',
    'searchHistory': '搜索历史',
    'favHideKeywords': '隐藏关键字',
  };

  static String? _deviceName;

  static Future<String> deviceName() async {
    if (_deviceName != null) return _deviceName!;
    try {
      _deviceName = Platform.localHostname;
    } catch (_) {
      _deviceName = 'PiliPlus';
    }
    return _deviceName!;
  }

  /// 跨启动稳定的设备 ID
  static String deviceId() => Pref.lanDeviceId;

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

  /// 按勾选类别过滤快照 data
  static Map<String, dynamic> filterPayload(
    Map<String, dynamic> full, {
    List<String>? categories,
  }) {
    final cats = categories ?? Pref.lanSyncCategories;
    final data = full['data'];
    if (data is! Map) return full;
    final filtered = <String, dynamic>{};
    for (final c in cats) {
      if (data.containsKey(c)) filtered[c] = data[c];
    }
    final counts = {
      for (final e in filtered.entries)
        e.key: e.value is List ? (e.value as List).length : 0,
    };
    return {
      ...full,
      'counts': counts,
      'data': filtered,
      'categories': cats,
    };
  }

  static Map<String, dynamic> buildSnapshot({List<String>? categories}) {
    return filterPayload(LocalListIo.buildFullPayload(), categories: categories);
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

  bool get isTrusted => Pref.findLanTrustedPeer(deviceId) != null;

  String? get savedPin {
    final m = Pref.findLanTrustedPeer(deviceId);
    final p = m?['pin']?.toString();
    return (p != null && p.isNotEmpty) ? p : null;
  }

  @override
  bool operator ==(Object other) =>
      other is LanPeer && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

/// 本机作为同步源
class LocalLanSyncHost {
  LocalLanSyncHost._();
  static final LocalLanSyncHost instance = LocalLanSyncHost._();

  HttpServer? _http;
  RawDatagramSocket? _udp;
  StreamSubscription? _udpSub;
  String? pin;
  bool get isRunning => _http != null;

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
          _udp!.send(bytes, dg.address, LocalLanSync.udpPort);
        } catch (_) {}
      }
    });
  }

  Future<void> stop() async {
    await _udpSub?.cancel();
    _udpSub = null;
    _udp?.close();
    _udp = null;
    await _http?.close(force: true);
    _http = null;
    pin = null;
  }

  bool _authOk(HttpRequest req) {
    final qPin = req.uri.queryParameters['pin'] ?? '';
    if (pin != null && qPin == pin) return true;
    // 已配对设备：用其保存的 pin 作为长期口令（双方各自保存）
    final peerId = req.uri.queryParameters['deviceId'] ?? '';
    if (peerId.isNotEmpty) {
      final trusted = Pref.findLanTrustedPeer(peerId);
      if (trusted != null) {
        final saved = trusted['pin']?.toString();
        if (saved != null && saved.isNotEmpty && qPin == saved) return true;
        // 无 pin 字段时允许仅 deviceId（弱，仅局域网）
        if (saved == null || saved.isEmpty) return true;
      }
    }
    return false;
  }

  Future<void> _handleHttp(HttpRequest req, String name, String id) async {
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'Content-Type');
    final path = req.uri.path;

    if (req.method == 'OPTIONS') {
      res.statusCode = 204;
      await res.close();
      return;
    }

    List<String>? catsFromQuery() {
      final c = req.uri.queryParameters['categories'];
      if (c == null || c.isEmpty) return null;
      return c.split(',').where((e) => e.isNotEmpty).toList();
    }

    if (path == '/info' && req.method == 'GET') {
      final payload = LocalLanSync.buildSnapshot();
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'name': name,
        'deviceId': id,
        'service': LocalLanSync.serviceName,
        'counts': payload['counts'] ?? {},
        'exportedAt': payload['exportedAt'],
      }));
      await res.close();
      return;
    }

    if (path == '/snapshot' && req.method == 'GET') {
      if (!_authOk(req)) {
        res.statusCode = 403;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'error': 'invalid_pin'}));
        await res.close();
        return;
      }
      final payload = LocalLanSync.buildSnapshot(categories: catsFromQuery());
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(payload));
      await res.close();
      return;
    }

    // 对方推送数据到本机合并
    if (path == '/push' && req.method == 'POST') {
      if (!_authOk(req)) {
        res.statusCode = 403;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'error': 'invalid_pin'}));
        await res.close();
        return;
      }
      final body = await utf8.decoder.bind(req).join();
      try {
        final decoded = jsonDecode(body);
        if (decoded is! Map) {
          res.statusCode = 400;
          res.write(jsonEncode({'error': 'invalid_body'}));
          await res.close();
          return;
        }
        await LocalListIo.applyDecodedMap(
          Map<String, dynamic>.from(decoded),
          replace: false,
        );
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'ok': true}));
      } catch (e) {
        res.statusCode = 500;
        res.write(jsonEncode({'error': '$e'}));
      }
      await res.close();
      return;
    }

    res.statusCode = 404;
    await res.close();
  }
}

class LocalLanSyncClient {
  LocalLanSyncClient._();

  static Future<List<LanPeer>> discover({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final found = <String, LanPeer>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      final probe = utf8.encode(LocalLanSync.magicProbe);
      final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
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
          final json =
              jsonDecode(msg.substring(LocalLanSync.magicAnnounce.length + 1));
          if (json is! Map) return;
          final port = json['port'];
          final deviceId = '${json['deviceId'] ?? ''}';
          final name = '${json['name'] ?? 'PiliPlus'}';
          final p =
              port is int ? port : int.tryParse('$port') ?? LocalLanSync.httpPort;
          if (deviceId.isEmpty || deviceId == LocalLanSync.deviceId()) return;
          found[deviceId] = LanPeer(
            name: name,
            host: dg.address.address,
            port: p,
            deviceId: deviceId,
          );
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

  static Future<bool> pullAndMerge({
    required LanPeer peer,
    required String pin,
    bool replace = false,
    List<String>? categories,
    bool remember = true,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    client.idleTimeout = const Duration(seconds: 20);
    try {
      final cats = categories ?? Pref.lanSyncCategories;
      final q = {
        'pin': pin,
        'deviceId': LocalLanSync.deviceId(),
        if (cats.isNotEmpty) 'categories': cats.join(','),
      };
      final uri = Uri.parse('${peer.endpoint}/snapshot').replace(queryParameters: q);
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 403) {
        SmartDialog.showToast('PIN 错误或未授权');
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
      if (remember) {
        Pref.upsertLanTrustedPeer(
          deviceId: peer.deviceId,
          name: peer.name,
          host: peer.host,
          port: peer.port,
          pin: pin,
        );
      }
      return true;
    } catch (e) {
      SmartDialog.showToast('同步失败：$e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 将本机快照推送到对方（对方需开启同步源）
  static Future<bool> pushToPeer({
    required LanPeer peer,
    required String pin,
    List<String>? categories,
    bool remember = true,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final payload = LocalLanSync.buildSnapshot(categories: categories);
      final q = {
        'pin': pin,
        'deviceId': LocalLanSync.deviceId(),
      };
      final uri = Uri.parse('${peer.endpoint}/push').replace(queryParameters: q);
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(payload));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 403) {
        SmartDialog.showToast('PIN 错误或未授权');
        return false;
      }
      if (res.statusCode != 200) {
        SmartDialog.showToast('推送失败：HTTP ${res.statusCode}');
        return false;
      }
      if (remember) {
        Pref.upsertLanTrustedPeer(
          deviceId: peer.deviceId,
          name: peer.name,
          host: peer.host,
          port: peer.port,
          pin: pin,
        );
      }
      // 解析 ok
      try {
        final m = jsonDecode(body);
        if (m is Map && m['ok'] == true) {
          SmartDialog.showToast('已推送到对方');
          return true;
        }
      } catch (_) {}
      SmartDialog.showToast('已推送');
      return true;
    } catch (e) {
      SmartDialog.showToast('推送失败：$e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 启动后自动：扫描已配对设备并静默合并（需开启设置）
  static Future<void> autoSyncOnce() async {
    if (!Pref.enableLocalFeatures || !Pref.enableLanAutoSync) return;
    final trusted = Pref.lanTrustedPeers;
    if (trusted.isEmpty) return;
    try {
      final peers = await discover(timeout: const Duration(seconds: 2));
      for (final peer in peers) {
        final t = Pref.findLanTrustedPeer(peer.deviceId);
        if (t == null) continue;
        final pin = t['pin']?.toString() ?? '';
        if (pin.isEmpty) continue;
        await pullAndMerge(
          peer: peer,
          pin: pin,
          replace: false,
          remember: true,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('autoSyncOnce: $e');
    }
  }
}
