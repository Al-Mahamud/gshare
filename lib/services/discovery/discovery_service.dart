import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/net.dart';
import '../../core/peer_client.dart';
import '../../platform/native_bridge.dart';
import 'mdns_discovery.dart';
import 'multicast_discovery.dart';

/// Finds nearby gshare devices. Every candidate is confirmed over TLS before it is listed.
class DiscoveryService extends ChangeNotifier {
  DiscoveryService({required this.self});

  final DeviceInfo Function() self;
  final Map<String, DeviceInfo> _devices = {};
  final Set<String> _inFlight = {};
  final MulticastDiscovery _multicast = MulticastDiscovery();
  final MdnsDiscovery _mdns = MdnsDiscovery();
  bool _scanning = false;

  bool get scanning => _scanning;

  List<DeviceInfo> get devices =>
      _devices.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  String _mdnsName(DeviceInfo me) => '${me.name} ${me.shortId}';

  Future<void> start() async {
    await NativeBridge.acquireMulticastLock();
    final me = self();
    await _multicast.start(selfId: me.id, port: me.port, onPeer: _onCandidate);
    await _mdns.start(name: _mdnsName(me), port: me.port, onPeer: _onCandidate);
    unawaited(scan());
  }

  /// Re-advertise after the device name changes.
  Future<void> restartAdvertising() async {
    final me = self();
    await _mdns.advertise(name: _mdnsName(me), port: me.port);
    _multicast.announce();
  }

  Future<void> refresh() async {
    _devices.clear();
    notifyListeners();
    _multicast.announce();
    await scan();
  }

  void _onCandidate(String ip, int port) => unawaited(probe(ip, port));

  Future<DeviceInfo?> probe(String ip, int port,
      {String? expectedId, Duration timeout = const Duration(seconds: 3)}) async {
    final key = '$ip:$port';
    if (!_inFlight.add(key)) return null;
    try {
      final info = await PeerClient.fetchInfo(ip, port, expectedId: expectedId, timeout: timeout);
      if (info == null || info.id == self().id) return null;
      _devices[info.id] = info;
      notifyListeners();
      return info;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Probes every host in the local /24 networks. This is what finds peers on a hotspot.
  Future<void> scan() async {
    if (_scanning) return;
    _scanning = true;
    notifyListeners();
    try {
      final hosts = await subnetHosts();
      await runPool<String>(hosts, 48, (ip) async {
        await probe(ip, kDefaultPort, timeout: const Duration(milliseconds: 900));
      });
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  /// Tries each address until one answers (QR code or typed address).
  Future<DeviceInfo?> connectManual(List<String> ips, int port, {String? expectedId}) async {
    for (final ip in ips) {
      final info = await probe(ip.trim(), port, expectedId: expectedId);
      if (info != null) return info;
    }
    return null;
  }

  Future<void> stop() async {
    _multicast.stop();
    await _mdns.stop();
    await NativeBridge.releaseMulticastLock();
  }
}
