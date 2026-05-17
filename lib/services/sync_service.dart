import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// 简单的局域网 WebSocket 同步服务（单文件最小实现）
class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  bool get isConnected => _channel != null || _clients.isNotEmpty;
  RawDatagramSocket? _discoverySocket;
  int _wsPort = 0;
  final int _discoveryPort = 41234;
  static const String _hostsBoxName = 'sync_hosts_box';

  Future<void> saveHost(Map<String, dynamic> host) async {
    try {
      Box box;
      if (Hive.isBoxOpen(_hostsBoxName)) {
        box = Hive.box(_hostsBoxName);
      } else {
        box = await Hive.openBox(_hostsBoxName);
      }
      // 避免重复：使用 host:port 作为唯一键，先移除已存在的相同项
      final existingKeys = box.keys.toList();
      for (final k in existingKeys) {
        final val = box.get(k);
        if (val is Map) {
          final h = val['host'];
          final p = val['port'];
          if (h == host['host'] && p == host['port']) {
            await box.delete(k);
          }
        }
      }
      await box.add(host);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getSavedHosts() async {
    try {
      Box box;
      if (Hive.isBoxOpen(_hostsBoxName)) {
        box = Hive.box(_hostsBoxName);
      } else {
        box = await Hive.openBox(_hostsBoxName);
      }
      final List<Map<String, dynamic>> out = [];
      for (final v in box.values) {
        if (v is Map) out.add(Map<String, dynamic>.from(v));
      }
      return out.reversed.toList();
    } catch (_) {}
    return [];
  }

  Future<void> removeSavedHostAt(int index) async {
    try {
      Box box;
      if (Hive.isBoxOpen(_hostsBoxName)) {
        box = Hive.box(_hostsBoxName);
      } else {
        box = await Hive.openBox(_hostsBoxName);
      }
      // keys are numeric indices starting from 0; use keys.elementAt
      final keys = box.keys.toList();
      if (index >= 0 && index < keys.length) {
        final key = keys[keys.length - 1 - index];
        await box.delete(key);
      }
    } catch (_) {}
  }

  final List<void Function(bool)> _connHandlers = [];
  String? _serverToken;

  void Function(Map<String, dynamic>)? _onRemoteEvent;

  /// 注册远端事件回调
  void registerRemoteHandler(void Function(Map<String, dynamic>) handler) {
    _onRemoteEvent = handler;
  }

  /// 注册连接状态回调（connected: true/false）
  void registerConnectionHandler(void Function(bool) handler) {
    _connHandlers.add(handler);
  }

  void _notifyConnection(bool connected) {
    for (final h in List<void Function(bool)>.from(_connHandlers)) {
      try {
        h(connected);
      } catch (_) {}
    }
  }

  /// 作为主机启动 WebSocket server，接受局域网内的连接并广播消息
  Future<void> startServer({
    int port = 4040,
    InternetAddress? bindAddress,
    String? token,
  }) async {
    await stopServer();
    final bind = bindAddress ?? InternetAddress.anyIPv4;
    _serverToken = token;
    _server = await HttpServer.bind(bind, port);
    _wsPort = port;
    // 启动 UDP discovery responder
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
      );
      _discoverySocket!.listen((ev) {
        if (ev == RawSocketEvent.read) {
          final dg = _discoverySocket!.receive();
          if (dg == null) return;
          try {
            final msg = String.fromCharCodes(dg.data);
            if (msg == 'DISCOVER_HELLO_FLUTTER') {
              final payload = json.encode({
                'port': _wsPort,
                'token': _serverToken,
              });
              _discoverySocket!.send(payload.codeUnits, dg.address, dg.port);
            }
          } catch (_) {}
        }
      });
    } catch (_) {}
    _server!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        try {
          // 验证配对 token（通过查询参数 token）
          final reqToken = request.uri.queryParameters['token'];
          if (_serverToken != null && _serverToken != reqToken) {
            request.response.statusCode = HttpStatus.unauthorized;
            await request.response.close();
            return;
          }
          final ws = await WebSocketTransformer.upgrade(request);
          _clients.add(ws);
          if (_clients.length == 1) _notifyConnection(true);
          ws.listen(
            (message) {
              try {
                final data =
                    json.decode(message as String) as Map<String, dynamic>;
                // 将远端消息回调给应用
                if (_onRemoteEvent != null) _onRemoteEvent!(data);
                // 广播给其他客户端
                for (final c in List<WebSocket>.from(_clients)) {
                  if (!identical(c, ws)) {
                    try {
                      c.add(message);
                    } catch (_) {}
                  }
                }
              } catch (_) {}
            },
            onDone: () {
              _clients.remove(ws);
              if (_clients.isEmpty) _notifyConnection(false);
            },
            onError: (_) {
              _clients.remove(ws);
              if (_clients.isEmpty) _notifyConnection(false);
            },
          );
        } catch (_) {}
      } else {
        // 非 WebSocket 请求返回 404
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
  }

  Future<void> stopServer() async {
    for (final c in List<WebSocket>.from(_clients)) {
      try {
        await c.close();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    try {
      _discoverySocket?.close();
    } catch (_) {}
    _discoverySocket = null;
    _notifyConnection(false);
  }

  /// 作为客户端连接到主机
  Future<void> connect(String host, int port) async {
    await disconnect();
    final uri = Uri.parse('ws://$host:$port');
    _channel = IOWebSocketChannel.connect(uri.toString());
    _sub = _channel!.stream.listen(
      _handleMessage,
      onDone: () => _cleanup(),
      onError: (_) => _cleanup(),
    );
    _notifyConnection(true);
  }

  /// 通过 UDP 广播发现局域网内的服务（返回 [{host,port,token}]）
  Future<List<Map<String, dynamic>>> discoverHosts({
    int discoveryPort = 41234,
    int timeoutMs = 2000,
  }) async {
    final List<Map<String, dynamic>> results = [];
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final message = 'DISCOVER_HELLO_FLUTTER';
      socket.send(
        message.codeUnits,
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
      final completer = Completer<void>();
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket!.receive();
          if (dg == null) return;
          try {
            final str = String.fromCharCodes(dg.data);
            final Map<String, dynamic> data =
                json.decode(str) as Map<String, dynamic>;
            data['host'] = dg.address.address;
            results.add(data);
          } catch (_) {}
        }
      });
      Future.delayed(Duration(milliseconds: timeoutMs), () {
        completer.complete();
      });
      await completer.future;
    } catch (_) {}
    try {
      socket?.close();
    } catch (_) {}
    return results;
  }

  /// 作为客户端连接到主机，并可提供配对 token
  Future<void> connectWithToken(String host, int port, String? token) async {
    await disconnect();
    final q = token != null ? '?token=${Uri.encodeComponent(token)}' : '';
    final uri = Uri.parse('ws://$host:$port$q');
    _channel = IOWebSocketChannel.connect(uri.toString());
    _sub = _channel!.stream.listen(
      _handleMessage,
      onDone: () => _cleanup(),
      onError: (_) => _cleanup(),
    );
    _notifyConnection(true);
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _notifyConnection(false);
  }

  void _cleanup() {
    _sub = null;
    _channel = null;
    _notifyConnection(false);
  }

  void _handleMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = json.decode(message as String);
      if (_onRemoteEvent != null) {
        _onRemoteEvent!(data);
      }
    } catch (_) {}
  }

  /// 发送事件到远端
  void sendEvent(Map<String, dynamic> payload) {
    try {
      if (_channel != null) {
        _channel!.sink.add(json.encode(payload));
        return;
      }
      if (_clients.isNotEmpty) {
        final msg = json.encode(payload);
        for (final c in List<WebSocket>.from(_clients)) {
          try {
            c.add(msg);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
