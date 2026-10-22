import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';

/// UDP multicast announcements. Not used on iOS, which needs Apple's multicast entitlement.
class MulticastDiscovery {
  RawDatagramSocket? _socket;
  Timer? _timer;
  String _selfId = '';
  int _port = kDefaultPort;
  void Function(String ip, int port)? _onPeer;
  final InternetAddress _group = InternetAddress(kMulticastGroup);

  Future<void> start({
    required String selfId,
    required int port,
    required void Function(String ip, int port) onPeer,
  }) async {
    if (Platform.isIOS || _socket != null) return;
    _selfId = selfId;
    _port = port;
    _onPeer = onPeer;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kMulticastPort, reuseAddress: true);
      socket.multicastLoopback = false;
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        try {
          socket.joinMulticast(_group, iface);
        } catch (_) {}
      }
      socket.listen(_onEvent);
      _socket = socket;
      announce();
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => announce());
    } catch (e) {
      debugPrint('multicast unavailable: $e');
    }
  }

  void announce({InternetAddress? to, bool reply = false}) {
    final socket = _socket;
    if (socket == null) return;
    final msg = utf8.encode(jsonEncode({
      'app': kAppName,
      'v': kProtocolVersion,
      'id': _selfId,
      'port': _port,
      'reply': reply,
    }));
    try {
      socket.send(msg, to ?? _group, kMulticastPort);
    } catch (_) {}
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    try {
      final msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (msg['app'] != kAppName || msg['id'] == _selfId) return;
      _onPeer?.call(dg.address.address, (msg['port'] as num).toInt());
      if (msg['reply'] != true) announce(to: dg.address, reply: true);
    } catch (_) {}
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}
