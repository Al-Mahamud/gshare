import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'constants.dart';
import 'util.dart';

enum DevicePlatform {
  android('Android'),
  ios('iPhone'),
  windows('Windows'),
  macos('Mac'),
  linux('Linux'),
  unknown('Device');

  const DevicePlatform(this.label);
  final String label;

  static DevicePlatform get current {
    if (Platform.isAndroid) return DevicePlatform.android;
    if (Platform.isIOS) return DevicePlatform.ios;
    if (Platform.isWindows) return DevicePlatform.windows;
    if (Platform.isMacOS) return DevicePlatform.macos;
    if (Platform.isLinux) return DevicePlatform.linux;
    return DevicePlatform.unknown;
  }

  static DevicePlatform parse(String? name) =>
      DevicePlatform.values.firstWhere((e) => e.name == name, orElse: () => DevicePlatform.unknown);

  bool get isMobile => this == DevicePlatform.android || this == DevicePlatform.ios;
}

@immutable
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.port,
    this.protocol = kProtocolVersion,
    this.ip,
  });

  /// SHA-256 fingerprint of the device certificate.
  final String id;
  final String name;
  final DevicePlatform platform;
  final int port;
  final int protocol;
  final String? ip;

  String get shortId => id.length >= 8 ? id.substring(0, 8) : id;

  DeviceInfo copyWith({String? ip, String? name}) => DeviceInfo(
        id: id,
        name: name ?? this.name,
        platform: platform,
        port: port,
        protocol: protocol,
        ip: ip ?? this.ip,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform.name,
        'port': port,
        'protocol': protocol,
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Unknown device',
        platform: DevicePlatform.parse(j['platform'] as String?),
        port: (j['port'] as num).toInt(),
        protocol: (j['protocol'] as num?)?.toInt() ?? 1,
      );
}

enum ItemKind { file, text }

class TransferItem {
  TransferItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.size,
    required this.mime,
    this.text,
    this.path,
  });

  final String id;
  final ItemKind kind;
  final String name;
  final int size;
  final String mime;

  /// Inline content for text items.
  final String? text;

  /// Local source path (sender side only, never sent).
  final String? path;

  static Future<TransferItem> fromFile(String path) async {
    final name = p.basename(path);
    return TransferItem(
      id: randomId(8),
      kind: ItemKind.file,
      name: name,
      size: await File(path).length(),
      mime: mimeFromName(name),
      path: path,
    );
  }

  factory TransferItem.text(String text) => TransferItem(
        id: randomId(8),
        kind: ItemKind.text,
        name: 'Text',
        size: utf8.encode(text).length,
        mime: 'text/plain',
        text: text,
      );

  TransferItem copyWith({String? name}) =>
      TransferItem(id: id, kind: kind, name: name ?? this.name, size: size, mime: mime, text: text, path: path);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'size': size,
        'mime': mime,
        if (text != null) 'text': text,
      };

  factory TransferItem.fromJson(Map<String, dynamic> j) => TransferItem(
        id: j['id'] as String,
        kind: j['kind'] == 'text' ? ItemKind.text : ItemKind.file,
        name: j['name'] as String? ?? 'file',
        size: (j['size'] as num?)?.toInt() ?? 0,
        mime: j['mime'] as String? ?? 'application/octet-stream',
        text: j['text'] as String?,
      );
}

enum Direction { send, receive }

enum TransferStatus {
  pending('Preparing'),
  waitingAccept('Waiting'),
  inProgress('Transferring'),
  done('Done'),
  failed('Failed'),
  cancelled('Cancelled'),
  declined('Declined');

  const TransferStatus(this.label);
  final String label;

  bool get isActive => this == pending || this == waitingAccept || this == inProgress;
}

class ItemProgress {
  ItemProgress(this.item);

  final TransferItem item;
  int bytes = 0;
  TransferStatus status = TransferStatus.pending;
  String? savedPath;
  String? note;
  String? error;
}

class TransferSession extends ChangeNotifier {
  TransferSession({
    required this.direction,
    required this.peer,
    required List<TransferItem> items,
    String? id,
    this.verified = false,
  })  : id = id ?? randomId(16),
        items = [for (final i in items) ItemProgress(i)],
        createdAt = DateTime.now();

  final String id;
  final Direction direction;
  final DeviceInfo peer;
  final List<ItemProgress> items;
  final DateTime createdAt;
  bool verified;

  /// Session id on the receiver (sender side only).
  String? remoteId;
  TransferStatus status = TransferStatus.pending;
  String? error;
  bool cancelRequested = false;

  int get totalBytes => items.fold<int>(0, (s, i) => s + i.item.size);
  int get doneBytes => items.fold<int>(0, (s, i) => s + i.bytes);
  bool get isActive => status.isActive;

  double get progress {
    final total = totalBytes;
    if (total == 0) return status == TransferStatus.done ? 1 : 0;
    return (doneBytes / total).clamp(0, 1).toDouble();
  }

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Throttled to keep progress updates cheap.
  void update({bool force = false}) {
    final now = DateTime.now();
    if (force || now.difference(_lastNotify) > const Duration(milliseconds: 120)) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  void setStatus(TransferStatus s, [String? err]) {
    status = s;
    error = err;
    update(force: true);
  }
}
