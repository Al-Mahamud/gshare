import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../platform/native_bridge.dart';
import '../services/app_services.dart';
import 'widgets.dart';

/// For when there is no shared Wi-Fi. Android can host a hotspot in-app; other platforms use the system one.
class HotspotScreen extends StatefulWidget {
  const HotspotScreen({super.key});

  @override
  State<HotspotScreen> createState() => _HotspotScreenState();
}

class _HotspotScreenState extends State<HotspotScreen> {
  HotspotInfo? _info;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      NativeBridge.getHotspot().then((info) {
        if (mounted) setState(() => _info = info);
      });
      NativeBridge.onHotspotStopped = () {
        if (mounted) setState(() => _info = null);
      };
    }
  }

  @override
  void dispose() {
    NativeBridge.onHotspotStopped = null;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Android 8-12 need location; 13+ need nearby Wi-Fi devices.
      await [Permission.locationWhenInUse, Permission.nearbyWifiDevices].request();
      final info = await NativeBridge.startHotspot();
      if (mounted) setState(() => _info = info);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    await NativeBridge.stopHotspot();
    if (mounted) setState(() => _info = null);
  }

  Future<void> _scanAndClose() async {
    unawaited(AppServices.I.discovery.refresh());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hotspot')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'No shared Wi-Fi? One device creates a hotspot and the other joins it. '
            'The hotspot has no internet; gshare only needs the local connection.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (Platform.isAndroid) ..._androidHost(theme) else ..._systemHotspotSteps(theme),
          const SizedBox(height: 24),
          const SectionHeader('Joining someone else\'s hotspot'),
          const Text(
            'Scan the Wi-Fi QR code with your camera app, or pick the network in Wi-Fi settings. '
            'Then come back and tap the button below.',
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _scanAndClose,
            icon: const Icon(Icons.radar),
            label: const Text('Scan for devices'),
          ),
        ],
      ),
    );
  }

  List<Widget> _androidHost(ThemeData theme) {
    final info = _info;
    if (info == null) {
      return [
        FilledButton.icon(
          onPressed: _busy ? null : _start,
          icon: const Icon(Icons.wifi_tethering),
          label: Text(_busy ? 'Starting…' : 'Start hotspot on this phone'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
      ];
    }
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text('Hotspot is on', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(data: info.wifiQr, size: 200, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text('Scan with the other device\'s camera to join', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wifi),
                title: const Text('Network'),
                subtitle: SelectableText(info.ssid),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.key),
                title: const Text('Password'),
                subtitle: SelectableText(info.password),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _stop, icon: const Icon(Icons.stop), label: const Text('Stop hotspot')),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Keep gshare open on this phone. Android turns the hotspot off when the app closes.',
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  List<Widget> _systemHotspotSteps(ThemeData theme) {
    final steps = Platform.isIOS
        ? const [
            'Open Settings → Personal Hotspot.',
            'Turn on "Allow Others to Join" and note the password.',
            'Join this iPhone\'s network on the other device.',
          ]
        : Platform.isWindows
            ? const [
                'Open Settings → Network & internet → Mobile hotspot.',
                'Turn it on and note the network name and password.',
                'Join that network on the other device.',
              ]
            : const [
                'This computer cannot create a hotspot from gshare.',
                'Start a hotspot on an Android phone with gshare, or use a phone\'s personal hotspot.',
                'Join that network from this computer.',
              ];
    return [
      const SectionHeader('Use this device\'s hotspot'),
      for (var i = 0; i < steps.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
          title: Text(steps[i]),
        ),
    ];
  }
}
