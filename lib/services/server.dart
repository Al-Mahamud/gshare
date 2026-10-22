import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/identity.dart';
import '../core/models.dart';
import 'http_util.dart';
import 'receive_manager.dart';

/// HTTPS server that receives transfers (see docs/PROTOCOL.md).
class GshareServer {
  GshareServer({required this.identity, required this.selfInfo, required this.receiver});

  final Identity identity;
  final DeviceInfo Function() selfInfo;
  final ReceiveManager receiver;

  HttpServer? _server;
  int port = kDefaultPort;

  bool get isRunning => _server != null;

  Future<void> start(int preferredPort) async {
    final context = identity.serverContext();
    SocketException? lastError;
    for (var p = preferredPort; p < preferredPort + 10; p++) {
      try {
        _server = await HttpServer.bindSecure(InternetAddress.anyIPv4, p, context);
        port = p;
        break;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    final server = _server;
    if (server == null) throw lastError ?? const SocketException('No free port');
    server.idleTimeout = const Duration(seconds: 30);
    server.listen(_handle, onError: (Object e) => debugPrint('server error: $e'));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    final method = req.method;
    try {
      if (method == 'GET' && path == '$kApiBase/info') {
        await sendJson(req.response, 200, selfInfo().toJson());
      } else if (method == 'POST' && path == '$kApiBase/prepare') {
        await receiver.handlePrepare(req);
      } else if (method == 'POST' && path == '$kApiBase/upload') {
        await receiver.handleUpload(req);
      } else if (method == 'GET' && path == '$kApiBase/status') {
        await receiver.handleStatus(req);
      } else if (method == 'POST' && path == '$kApiBase/finish') {
        await receiver.handleFinish(req);
      } else if (method == 'POST' && path == '$kApiBase/cancel') {
        await receiver.handleCancel(req);
      } else {
        await sendJson(req.response, 404, {'error': 'not found'});
      }
    } catch (e) {
      debugPrint('request $method $path failed: $e');
      try {
        await sendJson(req.response, 500, {'error': e.toString()});
      } catch (_) {}
    }
  }
}
