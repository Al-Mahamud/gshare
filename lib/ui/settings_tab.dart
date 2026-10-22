import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/identity.dart';
import '../services/app_services.dart';
import 'widgets.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppServices.I;
    final settings = s.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final trusted = settings.trusted.entries.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Your name'),
              subtitle: Text(settings.deviceName),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _rename(context),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.verified_user_outlined),
              title: const Text('Auto-accept from trusted devices'),
              value: settings.autoAcceptTrusted,
              onChanged: (v) => unawaited(settings.setAutoAcceptTrusted(v)),
            ),
            if (Platform.isAndroid || Platform.isIOS)
              SwitchListTile(
                secondary: const Icon(Icons.photo_library_outlined),
                title: const Text('Save received photos and videos to the gallery'),
                value: settings.saveMediaToGallery,
                onChanged: (v) => unawaited(settings.setSaveMediaToGallery(v)),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SectionHeader('Trusted devices'),
            ),
            if (trusted.isEmpty)
              const ListTile(
                title: Text('No trusted devices yet'),
                subtitle: Text('Tick "Trust this device" when you accept a transfer.'),
              ),
            for (final e in trusted)
              ListTile(
                leading: const Icon(Icons.devices),
                title: Text(e.value),
                subtitle: Text(groupHex(e.key.substring(0, 16))),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => unawaited(settings.untrust(e.key)),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SectionHeader('About this device'),
            ),
            ListTile(
              title: const Text('Security fingerprint (SHA-256)'),
              subtitle: SelectableText(groupHex(s.identity.fingerprint)),
            ),
            ListTile(title: const Text('Listening port'), subtitle: Text('${s.server.port}')),
            const ListTile(
              title: Text('Protocol'),
              subtitle: Text('gshare v$kProtocolVersion · HTTPS with pinned certificates · local network only'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _rename(BuildContext context) async {
    final s = AppServices.I;
    final controller = TextEditingController(text: s.settings.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(controller: controller, autofocus: true, maxLength: 40),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await s.settings.setDeviceName(name);
    await s.discovery.restartAdvertising();
  }
}
