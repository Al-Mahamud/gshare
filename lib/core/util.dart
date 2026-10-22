import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

final Random _rng = Random.secure();

String randomId([int bytes = 16]) {
  final sb = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    sb.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

bool isSafeId(String? id) => id != null && _safeId.hasMatch(id);

String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '${value.toInt()} B';
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}

/// Reduces a peer-supplied name to a safe base name.
String sanitizeFileName(String name) {
  var n = name.replaceAll('\\', '/').split('/').last;
  n = n.replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '_').trim();
  while (n.startsWith('.')) {
    n = n.substring(1);
  }
  if (n.isEmpty) n = 'file';
  if (n.length > 180) {
    var ext = p.extension(n);
    if (ext.length > 20) ext = '';
    n = n.substring(0, 180 - ext.length) + ext;
  }
  return n;
}

Future<String> uniquePath(String dir, String name) async {
  final base = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  var candidate = p.join(dir, name);
  var i = 1;
  while (await File(candidate).exists() || await Directory(candidate).exists()) {
    candidate = p.join(dir, '$base ($i)$ext');
    i++;
  }
  return candidate;
}

const Map<String, String> _mimeByExt = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'bmp': 'image/bmp',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'm4v': 'video/x-m4v',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
  '3gp': 'video/3gpp',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'apk': 'application/vnd.android.package-archive',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'json': 'application/json',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

String mimeFromName(String name) {
  final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
  return _mimeByExt[ext] ?? 'application/octet-stream';
}

bool isImageMime(String mime) => mime.startsWith('image/');
bool isVideoMime(String mime) => mime.startsWith('video/');
