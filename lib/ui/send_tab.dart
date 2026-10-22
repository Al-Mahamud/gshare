import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../services/app_services.dart';
import 'qr_scan_screen.dart';
import 'widgets.dart';

bool get canScanQr => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

class SendTab extends StatelessWidget {
  const SendTab({super.key, required this.onSent});

  final VoidCallback onSent;

  @override
  Widget build(BuildContext context) {
    final s = AppServices.I;
    return ListenableBuilder(
      listenable: Listenable.merge([s.selection, s.discovery, s.settings]),
      builder: (context, _) {
        final items = s.selection.items;
        final devices = s.discovery.devices;
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SectionHeader('What to send'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _pick(FileType.any),
                  icon: const Icon(Icons.insert_drive_file_outlined),
                  label: const Text('Files'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _pick(FileType.media),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Photos & videos'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _addText(context),
                  icon: const Icon(Icons.notes),
                  label: const Text('Text'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing selected yet.', style: theme.textTheme.bodyMedium),
              )
            else ...[
              for (final it in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(iconForItem(it)),
                  title: Text(
                    it.kind == ItemKind.text ? (it.text ?? '') : it.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(it.kind == ItemKind.text ? 'Text message' : formatBytes(it.size)),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () => s.selection.remove(it),
                  ),
                ),
              Row(
                children: [
                  Text('${items.length} item(s) · ${formatBytes(s.selection.totalBytes)}',
                      style: theme.textTheme.bodySmall),
                  const Spacer(),
                  TextButton(onPressed: s.selection.clear, child: const Text('Clear')),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SectionHeader(
              'Nearby devices',
              trailing: s.discovery.scanning
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      tooltip: 'Scan again',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => unawaited(s.discovery.refresh()),
                    ),
            ),
            if (devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  s.discovery.scanning
                      ? 'Looking for devices…'
                      : 'No devices found. Open gshare on the other device and make sure both are on the same '
                          'Wi-Fi, or use the hotspot button at the top.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            for (final d in devices)
              Card(
                child: ListTile(
                  leading: Icon(platformIcon(d.platform)),
                  title: Text(d.name),
                  subtitle: Text('${d.ip}:${d.port}${s.settings.isTrusted(d.id) ? ' · trusted' : ''}'),
                  trailing: const Icon(Icons.send),
                  onTap: () => _sendTo(context, d),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canScanQr)
                  OutlinedButton.icon(
                    onPressed: () => _scanQr(context),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR code'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _enterAddress(context),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Enter address'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _pick(FileType type) async {
    final files = await FilePicker.pickFiles(type: type);
    if (files.isEmpty) return;
    await AppServices.I.selection.addPaths(files.map((f) => f.path).whereType<String>());
  }

  Future<void> _addText(BuildContext context) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'Message, link or note'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    if (text != null) AppServices.I.selection.addText(text);
  }

  void _sendTo(BuildContext context, DeviceInfo device) {
    final s = AppServices.I;
    if (s.selection.items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick files, photos or text first.')));
      return;
    }
    s.sender.send(device, List.of(s.selection.items));
    s.selection.clear();
    onSent();
  }

  Future<void> _scanQr(BuildContext context) async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (value == null || !context.mounted) return;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'gshare' || uri.host != 'connect') {
      _snack(context, 'That is not a gshare code.');
      return;
    }
    final q = uri.queryParameters;
    final ips = (q['ip'] ?? '').split(',').where((e) => e.isNotEmpty).toList();
    final port = int.tryParse(q['port'] ?? '') ?? kDefaultPort;
    _snack(context, 'Connecting…');
    final device = await AppServices.I.discovery.connectManual(ips, port, expectedId: q['id']);
    if (!context.mounted) return;
    _snack(context, device == null ? 'Could not reach that device.' : 'Found ${device.name}.');
  }

  Future<void> _enterAddress(BuildContext context) async {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '$kDefaultPort');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect by address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'IP address', hintText: '192.168.1.23'),
            ),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Connect')),
        ],
      ),
    );
    final ip = ipController.text.trim();
    final port = int.tryParse(portController.text.trim()) ?? kDefaultPort;
    ipController.dispose();
    portController.dispose();
    if (ok != true || ip.isEmpty || !context.mounted) return;
    _snack(context, 'Connecting…');
    final device = await AppServices.I.discovery.connectManual([ip], port);
    if (!context.mounted) return;
    _snack(context, device == null ? 'No gshare device at $ip:$port.' : 'Found ${device.name}.');
  }

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}
