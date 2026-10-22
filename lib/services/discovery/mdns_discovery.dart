import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../../core/constants.dart';

/// Bonjour / NSD advertising and browsing for `_gshare._tcp`.
class MdnsDiscovery {
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;

  static bool get supported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;

  Future<void> start({
    required String name,
    required int port,
    required void Function(String ip, int port) onPeer,
  }) async {
    if (!supported) return;
    await advertise(name: name, port: port);
    if (_discovery != null) return;
    try {
      final discovery = await nsd.startDiscovery(kMdnsType, ipLookupType: nsd.IpLookupType.v4);
      discovery.addServiceListener((service, status) {
        if (status != nsd.ServiceStatus.found) return;
        final port = service.port;
        final addresses = service.addresses;
        if (port == null || addresses == null) return;
        for (final a in addresses) {
          if (a.type == InternetAddressType.IPv4) onPeer(a.address, port);
        }
      });
      _discovery = discovery;
    } catch (e) {
      debugPrint('mDNS discovery unavailable: $e');
    }
  }

  Future<void> advertise({required String name, required int port}) async {
    if (!supported) return;
    final old = _registration;
    _registration = null;
    if (old != null) {
      try {
        await nsd.unregister(old);
      } catch (_) {}
    }
    try {
      final safeName = name.length > 60 ? name.substring(0, 60) : name;
      _registration = await nsd.register(nsd.Service(name: safeName, type: kMdnsType, port: port));
    } catch (e) {
      debugPrint('mDNS advertise failed: $e');
    }
  }

  Future<void> stop() async {
    final reg = _registration;
    final disc = _discovery;
    _registration = null;
    _discovery = null;
    try {
      if (reg != null) await nsd.unregister(reg);
      if (disc != null) await nsd.stopDiscovery(disc);
    } catch (_) {}
  }
}
