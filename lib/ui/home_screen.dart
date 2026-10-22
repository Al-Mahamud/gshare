import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../platform/native_bridge.dart';
import '../services/app_services.dart';
import 'hotspot_screen.dart';
import 'receive_tab.dart';
import 'send_tab.dart';
import 'settings_tab.dart';
import 'transfers_tab.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AppServices _services = AppServices.I;
  int _tab = 0;
  bool _dialogOpen = false;
  late final AppLifecycleListener _lifecycle;

  static const _titles = ['Send', 'Receive', 'Transfers', 'Settings'];

  @override
  void initState() {
    super.initState();
    _services.receiver.addListener(_onIncoming);
    // Network may have changed while in the background.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_services.discovery.refresh()));
    NativeBridge.onShared = _loadShared;
    unawaited(_loadShared());
    if (Platform.isAndroid) unawaited(Permission.notification.request());
  }

  @override
  void dispose() {
    _services.receiver.removeListener(_onIncoming);
    _lifecycle.dispose();
    NativeBridge.onShared = null;
    super.dispose();
  }

  Future<void> _loadShared() async {
    final shared = await NativeBridge.takeSharedItems();
    if (shared == null || shared.isEmpty) return;
    await _services.selection.addPaths(shared.files);
    final text = shared.text;
    if (text != null) _services.selection.addText(text);
    if (mounted) setState(() => _tab = 0);
  }

  Future<void> _onIncoming() async {
    if (_dialogOpen || !mounted) return;
    final pending = _services.receiver.pending;
    if (pending.isEmpty) return;
    _dialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingRequestDialog(request: pending.first),
    );
    _dialogOpen = false;
    if (mounted) unawaited(_onIncoming());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Hotspot',
            icon: const Icon(Icons.wifi_tethering),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HotspotScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          SendTab(onSent: () => setState(() => _tab = 2)),
          const ReceiveTab(),
          const TransfersTab(),
          const SettingsTab(),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _services.log,
        builder: (context, _) {
          final active = _services.log.activeCount;
          return NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: 'Send'),
              const NavigationDestination(
                  icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Receive'),
              NavigationDestination(
                icon: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.swap_vert)),
                label: 'Transfers',
              ),
              const NavigationDestination(
                  icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
            ],
          );
        },
      ),
    );
  }
}
