import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../core/constants.dart';
import '../core/models.dart';
import '../core/peer_client.dart';
import '../platform/native_bridge.dart';
import 'transfer_log.dart';

class _Cancelled implements Exception {
  const _Cancelled({this.byReceiver = false});
  final bool byReceiver;
}

class SendManager {
  SendManager({required this.self, required this.log});

  final DeviceInfo Function() self;
  final TransferLog log;
  final Map<String, PeerClient> _clients = {};

  TransferSession send(DeviceInfo peer, List<TransferItem> items) {
    final session = TransferSession(direction: Direction.send, peer: peer, items: items, verified: true);
    log.add(session);
    unawaited(_run(session));
    return session;
  }

  void cancel(TransferSession session) {
    if (!session.isActive) return;
    session.cancelRequested = true;
    session.update(force: true);
    // Abort the open /prepare request; there is nothing else to interrupt yet.
    if (session.status == TransferStatus.waitingAccept) _clients[session.id]?.close();
  }

  Future<void> _run(TransferSession session) async {
    final client = PeerClient(session.peer);
    _clients[session.id] = client;
    NativeBridge.beginTransfer();
    try {
      session.setStatus(TransferStatus.waitingAccept);
      final prep = await client.postJson(
        '/prepare',
        {
          'sender': self().toJson(),
          'items': [for (final it in session.items) it.item.toJson()],
        },
        timeout: kAcceptTimeout + const Duration(seconds: 15),
      );
      if (session.cancelRequested) throw const _Cancelled();
      if (prep.status == 403) {
        session.setStatus(TransferStatus.declined, 'Declined by ${session.peer.name}');
        return;
      }
      if (prep.status != 200) {
        session.setStatus(TransferStatus.failed, '${prep.body['error'] ?? 'HTTP ${prep.status}'}');
        return;
      }

      session.remoteId = prep.body['sessionId'] as String;
      final tokens = (prep.body['tokens'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v'));
      session.setStatus(TransferStatus.inProgress);

      for (final it in session.items) {
        if (session.cancelRequested) throw const _Cancelled();
        if (it.item.kind == ItemKind.text) {
          it
            ..bytes = it.item.size
            ..status = TransferStatus.done;
          session.update(force: true);
          continue;
        }
        final token = tokens[it.item.id];
        if (token == null) throw HttpException('Receiver did not accept ${it.item.name}');
        await _sendFile(client, session, it, token);
      }
      session.setStatus(TransferStatus.done);
    } catch (e) {
      if (e is _Cancelled || session.cancelRequested) {
        final byReceiver = e is _Cancelled && e.byReceiver;
        session.setStatus(TransferStatus.cancelled, byReceiver ? 'Cancelled by ${session.peer.name}' : null);
        final remoteId = session.remoteId;
        if (!byReceiver && remoteId != null) {
          try {
            await client.postJson('/cancel', null,
                query: {'session': remoteId}, timeout: const Duration(seconds: 3));
          } catch (_) {}
        }
      } else {
        session.setStatus(TransferStatus.failed, describeError(e));
      }
    } finally {
      _clients.remove(session.id);
      client.close();
      NativeBridge.endTransfer();
    }
  }

  Future<void> _sendFile(PeerClient client, TransferSession session, ItemProgress it, String token) async {
    final remoteId = session.remoteId!;
    final file = File(it.item.path!);
    final size = it.item.size;
    final base = {'session': remoteId, 'item': it.item.id, 'token': token};
    var offset = 0;

    for (var attempt = 0;; attempt++) {
      try {
        if (attempt > 0) {
          final st = await client.getJson('/status', query: {'session': remoteId});
          if (st.status == 404 || st.status == 410) throw const _Cancelled(byReceiver: true);
          final items = st.body['items'] as Map?;
          offset = (items?[it.item.id] as num?)?.toInt() ?? 0;
        }
        it
          ..status = TransferStatus.inProgress
          ..bytes = offset;
        session.update(force: true);

        if (offset < size) {
          final req = await client.raw.postUrl(client.uri('/upload', {...base, 'offset': '$offset'}));
          req.contentLength = size - offset;
          req.headers.contentType = ContentType.binary;
          var sent = offset;
          await req.addStream(file.openRead(offset).map((chunk) {
            if (session.cancelRequested) throw const _Cancelled();
            sent += chunk.length;
            it.bytes = sent;
            session.update();
            return chunk;
          }));
          final res = await req.close();
          await res.drain<void>();
          if (res.statusCode == 404 || res.statusCode == 410) throw const _Cancelled(byReceiver: true);
          if (res.statusCode != 200) throw HttpException('Upload rejected (${res.statusCode})');
        }

        final digest = (await sha256.bind(file.openRead()).first).toString();
        final fin = await client.postJson('/finish', null,
            query: {...base, 'sha256': digest}, timeout: const Duration(minutes: 5));
        if (fin.status == 200) {
          it
            ..status = TransferStatus.done
            ..bytes = size
            ..error = null;
          session.update(force: true);
          return;
        }
        if (fin.status == 404 || fin.status == 410) throw const _Cancelled(byReceiver: true);
        throw HttpException('Receiver could not verify ${it.item.name} (${fin.status})');
      } on _Cancelled {
        rethrow;
      } catch (e) {
        if (session.cancelRequested) throw const _Cancelled();
        if (attempt >= 3) {
          it
            ..status = TransferStatus.failed
            ..error = describeError(e);
          rethrow;
        }
        it.error = 'Retrying: ${describeError(e)}';
        session.update(force: true);
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
  }
}
