import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../core/identity.dart';
import '../core/models.dart';
import '../core/peer_client.dart';
import '../core/settings.dart';
import '../core/util.dart';
import '../platform/native_bridge.dart';
import 'http_util.dart';
import 'transfer_log.dart';

/// A transfer waiting for the user to accept or decline.
class IncomingRequest {
  IncomingRequest(this.session, this.code);

  final TransferSession session;
  final String code;
  final Completer<bool> _completer = Completer<bool>();
  bool trust = false;

  Future<bool> get result => _completer.future;

  void respond(bool accept, {bool trust = false}) {
    if (_completer.isCompleted) return;
    this.trust = trust;
    _completer.complete(accept);
  }
}

class _Incoming {
  _Incoming(this.session, this.tokens, this.dir, this.partDir);

  final TransferSession session;
  final Map<String, String> tokens;
  final Directory dir;
  final Directory partDir;
  DateTime lastActivity = DateTime.now();

  File partial(String itemId) => File(p.join(partDir.path, '${session.id}_$itemId.part'));

  ItemProgress? item(String? id) {
    for (final i in session.items) {
      if (i.item.id == id) return i;
    }
    return null;
  }
}

class ReceiveManager extends ChangeNotifier {
  ReceiveManager({required this.identity, required this.settings, required this.log}) {
    _sweeper = Timer.periodic(const Duration(seconds: 30), (_) => _sweepIdle());
  }

  final Identity identity;
  final AppSettings settings;
  final TransferLog log;

  final List<IncomingRequest> pending = [];
  final Map<String, _Incoming> _sessions = {};
  late final Timer _sweeper;
  Directory? _dirCache;

  Future<Directory> receiveDirectory() async {
    final cached = _dirCache;
    if (cached != null) return cached;
    Directory base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      // Visible in the Files app (UIFileSharingEnabled).
      base = await getApplicationDocumentsDirectory();
    } else {
      base = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    }
    final dir = Directory(p.join(base.path, Platform.isIOS ? 'Received' : 'gshare'));
    await dir.create(recursive: true);
    return _dirCache = dir;
  }

  // POST /prepare
  Future<void> handlePrepare(HttpRequest req) async {
    final remoteIp = req.connectionInfo?.remoteAddress.address;
    final DeviceInfo sender;
    final List<TransferItem> items;
    try {
      final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      sender = DeviceInfo.fromJson(body['sender'] as Map<String, dynamic>).copyWith(ip: remoteIp);
      final raw = body['items'] as List;
      if (raw.isEmpty || raw.length > kMaxItemsPerSession) throw const FormatException('bad item count');
      items = [
        for (final r in raw) TransferItem.fromJson(r as Map<String, dynamic>),
      ];
      final ids = <String>{};
      for (final i in items) {
        if (!isSafeId(i.id) || !ids.add(i.id) || i.size < 0) throw FormatException('bad item ${i.id}');
      }
    } catch (e) {
      await sendJson(req.response, 400, {'error': 'invalid request: $e'});
      return;
    }
    if (sender.id == identity.fingerprint) {
      await sendJson(req.response, 400, {'error': 'cannot send to yourself'});
      return;
    }

    final verified = remoteIp != null &&
        await PeerClient.fetchInfo(remoteIp, sender.port, expectedId: sender.id) != null;
    final session = TransferSession(
      direction: Direction.receive,
      peer: sender,
      items: [for (final i in items) i.copyWith(name: sanitizeFileName(i.name))],
      verified: verified,
    );
    log.add(session);
    session.setStatus(TransferStatus.waitingAccept);

    var accepted = false;
    var trustNow = false;
    if (verified && settings.autoAcceptTrusted && settings.isTrusted(sender.id)) {
      accepted = true;
    } else {
      final request = IncomingRequest(session, verificationCode(identity.fingerprint, sender.id));
      pending.add(request);
      notifyListeners();
      final timer = Timer(kAcceptTimeout, () => request.respond(false));
      accepted = await request.result;
      timer.cancel();
      pending.remove(request);
      notifyListeners();
      trustNow = request.trust;
    }

    if (!accepted) {
      session.setStatus(TransferStatus.declined);
      await sendJson(req.response, 403, {'error': 'declined'});
      return;
    }
    if (trustNow && verified) await settings.trust(sender.id, sender.name);

    final dir = await receiveDirectory();
    final partDir = Directory(p.join(dir.path, '.partial'));
    await partDir.create(recursive: true);

    final tokens = <String, String>{};
    for (final it in session.items) {
      if (it.item.kind == ItemKind.text) {
        it.bytes = it.item.size;
        it.status = TransferStatus.done;
      } else {
        tokens[it.item.id] = randomId(16);
      }
    }
    final inc = _Incoming(session, tokens, dir, partDir);
    _sessions[session.id] = inc;
    NativeBridge.beginTransfer();
    session.setStatus(TransferStatus.inProgress);
    await sendJson(req.response, 200, {'sessionId': session.id, 'tokens': tokens});
    _checkComplete(inc);
  }

  /// Finds the session and item for a request, or replies with an error and returns null.
  Future<(_Incoming, ItemProgress)?> _lookupItem(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final inc = _sessions[q['session']];
    if (inc == null) {
      await sendJson(req.response, 404, {'error': 'unknown or finished session'});
      return null;
    }
    final item = inc.item(q['item']);
    final token = item == null ? null : inc.tokens[item.item.id];
    if (item == null || token == null || token != q['token']) {
      await sendJson(req.response, 403, {'error': 'invalid token'});
      return null;
    }
    if (inc.session.cancelRequested) {
      await sendJson(req.response, 410, {'error': 'cancelled'});
      return null;
    }
    inc.lastActivity = DateTime.now();
    return (inc, item);
  }

  // POST /upload?session=&item=&token=&offset=
  Future<void> handleUpload(HttpRequest req) async {
    final found = await _lookupItem(req);
    if (found == null) return;
    final (inc, it) = found;
    final offset = int.tryParse(req.uri.queryParameters['offset'] ?? '0') ?? 0;
    final file = inc.partial(it.item.id);
    final current = await file.exists() ? await file.length() : 0;
    if (offset != current) {
      await sendJson(req.response, 409, {'received': current});
      return;
    }
    if (req.contentLength > 0 && offset + req.contentLength > it.item.size) {
      await sendJson(req.response, 413, {'error': 'more data than announced'});
      return;
    }

    it.status = TransferStatus.inProgress;
    var received = current;
    final sink = file.openWrite(mode: FileMode.append);
    try {
      await sink.addStream(req.map((chunk) {
        if (inc.session.cancelRequested) throw const FileSystemException('cancelled');
        received += chunk.length;
        if (received > it.item.size) throw const FileSystemException('more data than announced');
        it.bytes = received;
        inc.lastActivity = DateTime.now();
        inc.session.update();
        return chunk;
      }));
    } finally {
      await sink.close();
    }
    inc.session.update(force: true);
    await sendJson(req.response, 200, {'received': received});
  }

  // GET /status?session=
  Future<void> handleStatus(HttpRequest req) async {
    final inc = _sessions[req.uri.queryParameters['session']];
    if (inc == null) {
      await sendJson(req.response, 404, {'error': 'unknown or finished session'});
      return;
    }
    inc.lastActivity = DateTime.now();
    final items = <String, int>{};
    for (final it in inc.session.items) {
      if (it.item.kind != ItemKind.file) continue;
      if (it.status == TransferStatus.done) {
        items[it.item.id] = it.item.size;
      } else {
        final f = inc.partial(it.item.id);
        items[it.item.id] = await f.exists() ? await f.length() : 0;
      }
    }
    await sendJson(req.response, 200, {'items': items});
  }

  // POST /finish?session=&item=&token=&sha256=
  Future<void> handleFinish(HttpRequest req) async {
    final found = await _lookupItem(req);
    if (found == null) return;
    final (inc, it) = found;
    if (it.status == TransferStatus.done) {
      await sendJson(req.response, 200, {'ok': true});
      return;
    }
    final file = inc.partial(it.item.id);
    if (!await file.exists() && it.item.size == 0) await file.create();
    final length = await file.exists() ? await file.length() : 0;
    if (length != it.item.size) {
      await sendJson(req.response, 409, {'received': length});
      return;
    }

    final digest = (await sha256.bind(file.openRead()).first).toString();
    if (digest != req.uri.queryParameters['sha256']) {
      await file.delete();
      it.bytes = 0;
      it.error = 'Checksum mismatch, retrying';
      inc.session.update(force: true);
      await sendJson(req.response, 422, {'error': 'checksum mismatch'});
      return;
    }

    final dest = await uniquePath(inc.dir.path, it.item.name);
    final moved = await file.rename(dest);
    it
      ..savedPath = moved.path
      ..bytes = it.item.size
      ..error = null
      ..status = TransferStatus.done;
    await sendJson(req.response, 200, {'ok': true});
    await _publish(it);
    _checkComplete(inc);
  }

  // POST /cancel?session=
  Future<void> handleCancel(HttpRequest req) async {
    final inc = _sessions[req.uri.queryParameters['session']];
    await sendJson(req.response, 200, {'ok': true});
    if (inc == null) return;
    inc.session
      ..cancelRequested = true
      ..setStatus(TransferStatus.cancelled, 'Cancelled by sender');
    await _close(inc, deletePartials: true);
  }

  /// Cancel from this device's UI. Also declines a request still waiting for an answer.
  Future<void> cancel(TransferSession session) async {
    for (final r in List.of(pending)) {
      if (r.session == session) r.respond(false);
    }
    final inc = _sessions[session.id];
    if (inc == null) return;
    session
      ..cancelRequested = true
      ..setStatus(TransferStatus.cancelled);
    await _close(inc, deletePartials: true);
  }

  Future<void> _publish(ItemProgress it) async {
    final path = it.savedPath;
    if (path == null) return;
    final mime = it.item.mime;
    final media = isImageMime(mime) || isVideoMime(mime);
    try {
      if ((Platform.isAndroid || Platform.isIOS) && media && settings.saveMediaToGallery) {
        if (!await Gal.hasAccess(toAlbum: true)) await Gal.requestAccess(toAlbum: true);
        if (isImageMime(mime)) {
          await Gal.putImage(path, album: kAppName);
        } else {
          await Gal.putVideo(path, album: kAppName);
        }
        it.note = 'Saved to gallery';
      } else if (Platform.isAndroid) {
        // Only Android 9 and older prompt; newer versions write through MediaStore.
        await Permission.storage.request();
        if (await NativeBridge.saveToDownloads(path, p.basename(path), mime)) {
          it.note = 'Saved to Downloads/gshare';
        }
      }
    } catch (e) {
      it.note = 'Kept in the app folder only';
      debugPrint('publish failed: $e');
    }
  }

  void _checkComplete(_Incoming inc) {
    final s = inc.session;
    if (s.items.every((i) => i.status == TransferStatus.done)) {
      s.setStatus(TransferStatus.done);
      unawaited(_close(inc));
    } else {
      s.update(force: true);
    }
  }

  Future<void> _close(_Incoming inc, {bool deletePartials = false}) async {
    if (_sessions.remove(inc.session.id) == null) return;
    NativeBridge.endTransfer();
    if (!deletePartials) return;
    for (final it in inc.session.items) {
      try {
        final f = inc.partial(it.item.id);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  void _sweepIdle() {
    final now = DateTime.now();
    for (final inc in List.of(_sessions.values)) {
      if (now.difference(inc.lastActivity) > kReceiveIdleTimeout) {
        inc.session.setStatus(TransferStatus.failed, 'Sender stopped responding');
        unawaited(_close(inc, deletePartials: true));
      }
    }
  }

  @override
  void dispose() {
    _sweeper.cancel();
    super.dispose();
  }
}
