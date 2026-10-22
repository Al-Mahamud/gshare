import 'dart:collection';
import 'dart:io';

bool isPrivateIPv4(InternetAddress a) {
  if (a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
}

/// Private IPv4 addresses of this device (Wi-Fi, hotspot, Ethernet).
Future<List<String>> localIPv4() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final out = <String>{};
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (isPrivateIPv4(a)) out.add(a.address);
      }
    }
    return out.toList();
  } catch (_) {
    return const [];
  }
}

/// Every other host in the /24 of each local address, gateway (.1) first.
Future<List<String>> subnetHosts() async {
  final own = await localIPv4();
  final hosts = <String>{};
  for (final ip in own) {
    final parts = ip.split('.');
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    for (var i = 1; i < 255; i++) {
      final host = '$prefix.$i';
      if (!own.contains(host)) hosts.add(host);
    }
  }
  return hosts.toList();
}

Future<void> runPool<T>(Iterable<T> items, int concurrency, Future<void> Function(T item) task) async {
  final queue = Queue<T>.of(items);
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final item = queue.removeFirst();
      try {
        await task(item);
      } catch (_) {}
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
}
