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
  /// 局域网组播地址（部分 WiFi 会屏蔽 255.255.255.255 广播）
  static final InternetAddress multicastAddr =
      InternetAddress('239.255.37.218');

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

  static bool _isPrivateLan(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]) ?? -1;
    final b = int.tryParse(p[1]) ?? -1;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  /// 是否像虚拟网卡 / VPN / 容器网段（展示时靠后）
  static bool _isLikelyVirtual(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return true;
    final a = int.tryParse(p[0]) ?? -1;
    final b = int.tryParse(p[1]) ?? -1;
    // 常见 Docker / Hyper-V / iOS 蜂窝共享 / 部分 VPN
    if (a == 198 && b == 19) return true; // 截图中的 198.19.0.1
    if (a == 172 && b == 17) return true;
    if (a == 100 && b == 64) return true; // CGNAT
    return false;
  }

  static Future<List<String>> localIPv4s({bool preferredFirst = true}) async {
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
    if (!preferredFirst) return out;
    out.sort((x, y) {
      int score(String ip) {
        if (_isPrivateLan(ip) && !_isLikelyVirtual(ip)) return 0;
        if (_isPrivateLan(ip)) return 1;
        return 2;
      }
      final c = score(x).compareTo(score(y));
      return c != 0 ? c : x.compareTo(y);
    });
    return out;
  }

  /// 给对方填写的推荐地址（优先 192.168/10/172.16 非虚拟）
  static Future<String?> recommendedLanIp() async {
    final list = await localIPv4s();
    for (final ip in list) {
      if (_isPrivateLan(ip) && !_isLikelyVirtual(ip)) return ip;
    }
    return list.isEmpty ? null : list.first;
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

  static Map<String, String> clientQuery({Map<String, String>? extra}) {
    return {
      'clientDeviceId': deviceId(),
      'clientName': _deviceName ?? 'PiliPlus',
      'clientPort': '$httpPort',
      ...?extra,
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
  Timer? _announceTimer;
  String? pin;
  bool get isRunning => _http != null;

  /// 主动连入本机的设备（对方能连你、你连不回时用这里的 IP）
  final Map<String, LanPeer> recentVisitors = {};
  final _visitorsCtrl = StreamController<List<LanPeer>>.broadcast();
  Stream<List<LanPeer>> get visitors$ => _visitorsCtrl.stream;
  List<LanPeer> get visitorList => recentVisitors.values.toList();

  void _noteVisitor({
    required String host,
    required String deviceId,
    required String name,
    int port = LocalLanSync.httpPort,
  }) {
    if (host.isEmpty || host == '127.0.0.1') return;
    if (deviceId.isEmpty) {
      deviceId = 'ip-$host';
    }
    if (deviceId == LocalLanSync.deviceId()) return;
    recentVisitors[deviceId] = LanPeer(
      name: name.isEmpty ? host : name,
      host: host,
      port: port,
      deviceId: deviceId,
    );
    if (!_visitorsCtrl.isClosed) {
      _visitorsCtrl.add(visitorList);
    }
  }

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
    try {
      _udp!.joinMulticast(LocalLanSync.multicastAddr);
    } catch (_) {}

    List<int> buildAnnounceBytes() {
      final announce = jsonEncode({
        'name': name,
        'port': LocalLanSync.httpPort,
        'deviceId': id,
        'pinRequired': true,
      });
      return utf8.encode('${LocalLanSync.magicAnnounce}|$announce');
    }

    Future<void> broadcastAnnounce([InternetAddress? to, int? port]) async {
      final bytes = buildAnnounceBytes();
      final targets = <InternetAddress>[
        InternetAddress('255.255.255.255'),
        LocalLanSync.multicastAddr,
      ];
      for (final ip in await LocalLanSync.localIPv4s()) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          targets.add(
            InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
          );
        }
      }
      if (to != null) {
        try {
          _udp!.send(bytes, to, port ?? LocalLanSync.udpPort);
        } catch (_) {}
      }
      for (final t in targets) {
        try {
          _udp!.send(bytes, t, LocalLanSync.udpPort);
        } catch (_) {}
      }
    }

    _udpSub = _udp!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = _udp!.receive();
      if (dg == null) return;
      final msg = utf8.decode(dg.data, allowMalformed: true);
      if (msg.startsWith(LocalLanSync.magicProbe)) {
        final bytes = buildAnnounceBytes();
        // 关键：单播回探测方的源地址/源端口（iOS 扫描依赖此路径）
        try {
          _udp!.send(bytes, dg.address, dg.port);
        } catch (_) {}
        try {
          _udp!.send(bytes, dg.address, LocalLanSync.udpPort);
        } catch (_) {}
        // 再广播，供监听固定端口的客户端
        broadcastAnnounce();
      }
    });

    // 主动周期宣告，避免对方探测包被路由器丢掉
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      broadcastAnnounce();
    });
    await broadcastAnnounce();
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    await _udpSub?.cancel();
    _udpSub = null;
    try {
      _udp?.leaveMulticast(LocalLanSync.multicastAddr);
    } catch (_) {}
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

    final remote = req.connectionInfo?.remoteAddress.address ?? '';
    final q = req.uri.queryParameters;
    final clientId = q['clientDeviceId'] ?? q['deviceId'] ?? '';
    final clientName = q['clientName'] ?? '';
    final clientPort =
        int.tryParse(q['clientPort'] ?? '') ?? LocalLanSync.httpPort;
    if (remote.isNotEmpty && path != '/') {
      _noteVisitor(
        host: remote,
        deviceId: clientId,
        name: clientName.isNotEmpty ? clientName : remote,
        port: clientPort,
      );
    }

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
      final addrs = await LocalLanSync.localIPv4s();
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'name': name,
        'deviceId': id,
        'service': LocalLanSync.serviceName,
        'counts': payload['counts'] ?? {},
        'exportedAt': payload['exportedAt'],
        'addresses': addrs,
        'port': LocalLanSync.httpPort,
        // 告诉对方：在我这边看到的你的地址（便于单向连通时填 IP）
        'clientSeenAs': remote,
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
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final found = <String, LanPeer>{};

    void addPeer({
      required String deviceId,
      required String name,
      required String host,
      required int port,
    }) {
      if (deviceId.isEmpty || deviceId == LocalLanSync.deviceId()) return;
      // 忽略本机回环
      if (host == '127.0.0.1' || host == '0.0.0.0') return;
      found[deviceId] = LanPeer(
        name: name,
        host: host,
        port: port,
        deviceId: deviceId,
      );
    }

    void parseAnnounce(String msg, String fromHost) {
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
        addPeer(
          deviceId: deviceId,
          name: name,
          host: fromHost,
          port: p,
        );
      } catch (_) {}
    }

    // ---- UDP：探测套接字(临时端口) + 监听套接字(固定端口收广播) ----
    RawDatagramSocket? sockProbe;
    RawDatagramSocket? sockListen;
    StreamSubscription? subProbe;
    StreamSubscription? subListen;
    Timer? timer;
    try {
      sockProbe = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      sockProbe.broadcastEnabled = true;

      // iOS 等客户端必须监听固定端口，才能收到 PC 主动宣告/广播
      try {
        sockListen = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          LocalLanSync.udpPort,
          reuseAddress: true,
        );
        sockListen.broadcastEnabled = true;
        try {
          sockListen.joinMulticast(LocalLanSync.multicastAddr);
        } catch (_) {}
        subListen = sockListen.listen((event) {
          if (event != RawSocketEvent.read) return;
          final dg = sockListen!.receive();
          if (dg == null) return;
          final msg = utf8.decode(dg.data, allowMalformed: true);
          parseAnnounce(msg, dg.address.address);
        });
      } catch (e) {
        // 本机已作同步源占用端口时忽略
        if (kDebugMode) debugPrint('discover listen 37218: $e');
      }

      try {
        sockProbe.joinMulticast(LocalLanSync.multicastAddr);
      } catch (_) {}

      final probe = utf8.encode(LocalLanSync.magicProbe);
      final targets = <InternetAddress>[
        InternetAddress('255.255.255.255'),
        LocalLanSync.multicastAddr,
      ];
      for (final ip in await LocalLanSync.localIPv4s()) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          targets.add(
            InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
          );
        }
      }

      void sendProbes() {
        for (final t in targets) {
          try {
            sockProbe!.send(probe, t, LocalLanSync.udpPort);
          } catch (_) {}
        }
      }

      subProbe = sockProbe.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = sockProbe!.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        parseAnnounce(msg, dg.address.address);
      });

      sendProbes();
      timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
        sendProbes();
      });

      await Future<void>.delayed(timeout);
    } catch (e) {
      if (kDebugMode) debugPrint('discover udp: $e');
    } finally {
      timer?.cancel();
      await subProbe?.cancel();
      await subListen?.cancel();
      try {
        sockProbe?.leaveMulticast(LocalLanSync.multicastAddr);
      } catch (_) {}
      try {
        sockListen?.leaveMulticast(LocalLanSync.multicastAddr);
      } catch (_) {}
      sockProbe?.close();
      sockListen?.close();
    }

    // ---- HTTP 扫同网段 /info（Windows 防火墙常拦 UDP，TCP 放行后仍可发现）----
    try {
      await _httpDiscover(found, addPeer);
    } catch (e) {
      if (kDebugMode) debugPrint('discover http: $e');
    }

    return found.values.toList();
  }

  static Future<void> _httpDiscover(
    Map<String, LanPeer> found,
    void Function({
      required String deviceId,
      required String name,
      required String host,
      required int port,
    }) addPeer,
  ) async {
    final bases = <String>{};
    for (final ip in await LocalLanSync.localIPv4s()) {
      final parts = ip.split('.');
      if (parts.length == 4) {
        bases.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }
    if (bases.isEmpty) return;

    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 350);
    client.idleTimeout = const Duration(milliseconds: 350);

    Future<void> tryHost(String host) async {
      try {
        final uri = Uri.parse(
          'http://$host:${LocalLanSync.httpPort}/info',
        ).replace(queryParameters: LocalLanSync.clientQuery());
        final req = await client.getUrl(uri);
        final res = await req.close().timeout(const Duration(milliseconds: 400));
        if (res.statusCode != 200) {
          await res.drain<void>();
          return;
        }
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        if (json is! Map) return;
        if ('${json['service']}' != LocalLanSync.serviceName &&
            json['deviceId'] == null) {
          return;
        }
        addPeer(
          deviceId: '${json['deviceId'] ?? ''}',
          name: '${json['name'] ?? 'PiliPlus'}',
          host: host,
          port: LocalLanSync.httpPort,
        );
      } catch (_) {}
    }

    // 优先扫常见网关段，再扫全段（限并发）
    final hosts = <String>[];
    for (final b in bases) {
      for (final last in [1, 2, 100, 101, 102, 200, 254]) {
        hosts.add('$b.$last');
      }
      for (var i = 1; i <= 254; i++) {
        final h = '$b.$i';
        if (!hosts.contains(h)) hosts.add(h);
      }
    }

    const concurrency = 48;
    // 限制总耗时约 6s，优先扫完常见地址
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    for (var i = 0; i < hosts.length; i += concurrency) {
      if (DateTime.now().isAfter(deadline)) break;
      final batch = hosts.sublist(i, min(i + concurrency, hosts.length));
      await Future.wait(batch.map(tryHost));
    }
    client.close(force: true);
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
        ...LocalLanSync.clientQuery(),
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
        ...LocalLanSync.clientQuery(),
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
