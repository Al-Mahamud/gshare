import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class SharedPayload {
  const SharedPayload(this.files, this.text);
  final List<String> files;
  final String? text;
  bool get isEmpty => files.isEmpty && (text == null || text!.isEmpty);
}

class HotspotInfo {
  const HotspotInfo({required this.ssid, required this.password, this.security = 1});

  final String ssid;
  final String password;

  /// Android SoftApConfiguration security type: 1 WPA2, 2 WPA3 transition, 3 WPA3.
  final int security;

  static String _esc(String s) => s.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');

  /// Standard Wi-Fi QR format, understood by the iOS and Android camera apps.
  String get wifiQr => 'WIFI:T:${security == 3 ? 'SAE' : 'WPA'};S:${_esc(ssid)};P:${_esc(password)};;';
}

/// Android-only native features (MainActivity.kt). Every call is a no-op elsewhere.
class NativeBridge {
  static const MethodChannel _ch = MethodChannel('gshare/native');

  static Future<void> Function()? onShared;
  static void Function()? onHotspotStopped;

  static bool get _android => Platform.isAndroid;

  static void init() {
    if (!_android) return;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'sharedReceived':
          await onShared?.call();
        case 'hotspotStopped':
          onHotspotStopped?.call();
      }
      return null;
    });
  }

  static Future<void> acquireMulticastLock() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod<void>('acquireMulticastLock');
    } catch (_) {}
  }

  static Future<void> releaseMulticastLock() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod<void>('releaseMulticastLock');
    } catch (_) {}
  }

  static int _activeTransfers = 0;

  /// Keeps an Android foreground service running while any transfer is active.
  static void beginTransfer() {
    if (_activeTransfers++ == 0) _setTransferActive(true);
  }

  static void endTransfer() {
    if (_activeTransfers == 0) return;
    if (--_activeTransfers == 0) _setTransferActive(false);
  }

  static void _setTransferActive(bool active) {
    if (!_android) return;
    unawaited(_ch.invokeMethod<void>('setTransferActive', {'active': active}).catchError((Object _) {}));
  }

  static HotspotInfo? _hotspotFromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    return HotspotInfo(
      ssid: m['ssid'] as String? ?? '',
      password: m['password'] as String? ?? '',
      security: (m['security'] as num?)?.toInt() ?? 1,
    );
  }

  /// Throws [PlatformException] with a readable message on failure.
  static Future<HotspotInfo?> startHotspot() async {
    if (!_android) return null;
    return _hotspotFromMap(await _ch.invokeMapMethod<String, dynamic>('startHotspot'));
  }

  static Future<void> stopHotspot() async {
    if (!_android) return;
    await _ch.invokeMethod<void>('stopHotspot');
  }

  static Future<HotspotInfo?> getHotspot() async {
    if (!_android) return null;
    try {
      return _hotspotFromMap(await _ch.invokeMapMethod<String, dynamic>('getHotspot'));
    } catch (_) {
      return null;
    }
  }

  /// Files and text handed to gshare through the Android share sheet.
  static Future<SharedPayload?> takeSharedItems() async {
    if (!_android) return null;
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('takeSharedItems');
      if (m == null) return null;
      final files = (m['files'] as List?)?.whereType<String>().toList() ?? const <String>[];
      return SharedPayload(files, m['text'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// Copies a file into the public Downloads/gshare folder (MediaStore).
  static Future<bool> saveToDownloads(String path, String name, String mime) async {
    if (!_android) return false;
    try {
      return await _ch.invokeMethod<bool>('saveToDownloads', {'path': path, 'name': name, 'mime': mime}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
