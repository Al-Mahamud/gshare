import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/models.dart';
import '../core/net.dart';
import '../services/app_services.dart';
import 'widgets.dart';

class ReceiveTab extends StatefulWidget {
  const ReceiveTab({super.key});

  @override
  State<ReceiveTab> createState() => _ReceiveTabState();
}

class _ReceiveTabState extends State<ReceiveTab> {
  late Future<List<String>> _ips = localIPv4();
  late final Future<Directory> _dir = AppServices.I.receiver.receiveDirectory();

  String _connectUri(List<String> ips) {
    final s = AppServices.I;
    return Uri(
      scheme: 'gshare',
      host: 'connect',
      queryParameters: {'ip': ips.join(','), 'port': '${s.server.port}', 'id': s.identity.fingerprint},
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.I;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.log]),
      builder: (context, _) {
        final recent = s.log.sessions.where((x) => x.direction == Direction.receive).take(5).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(radius: 32, child: Icon(platformIcon(DevicePlatform.current), size: 32)),
                    const SizedBox(height: 12),
                    Text(s.settings.deviceName, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                    Text('ID ${s.self.shortId}', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Chip(
                      avatar: Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 18),
                      label: Text(s.server.isRunning ? 'Ready to receive' : 'Not listening'),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<String>>(
                      future: _ips,
                      builder: (context, snap) {
                        final ips = snap.data ?? const <String>[];
                        if (snap.connectionState != ConnectionState.done) {
                          return const CircularProgressIndicator();
                        }
                        if (ips.isEmpty) {
                          return const Text('Not connected to Wi-Fi or a hotspot.');
                        }
                        return Column(
                          children: [
                            for (final ip in ips) SelectableText('$ip:${s.server.port}'),
                            const SizedBox(height: 16),
                            Container(
                              color: Colors.white,
                              padding: const EdgeInsets.all(8),
                              child: QrImageView(
                                data: _connectUri(ips),
                                size: 180,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Scan this from gshare on the other device',
                                style: theme.textTheme.bodySmall),
                          ],
                        );
                      },
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _ips = localIPv4()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh addresses'),
                    ),
                  ],
                ),
              ),
            ),
            FutureBuilder<Directory>(
              future: _dir,
              builder: (context, snap) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Received files are saved to'),
                subtitle: SelectableText(snap.data?.path ?? '…'),
              ),
            ),
            const SectionHeader('Recently received'),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing received yet.', style: theme.textTheme.bodyMedium),
              ),
            for (final session in recent) TransferTile(key: ValueKey(session.id), session: session),
          ],
        );
      },
    );
  }
}
