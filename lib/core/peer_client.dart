import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'constants.dart';
import 'identity.dart';
import 'models.dart';

class JsonResponse {
  const JsonResponse(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
}

Future<Map<String, dynamic>> readJsonBody(Stream<List<int>> stream) async {
  final text = await utf8.decodeStream(stream);
  if (text.trim().isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(text);
  return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{'data': decoded};
}

/// HTTPS client pinned to one peer's certificate fingerprint.
class PeerClient {
  PeerClient(this.peer, {Duration connectTimeout = const Duration(seconds: 5)})
      : raw = createPinnedClient(peer.id, connectTimeout);

  final DeviceInfo peer;
  final HttpClient raw;

  Uri uri(String path, [Map<String, String>? query]) => Uri(
        scheme: 'https',
        host: peer.ip,
        port: peer.port,
        path: '$kApiBase$path',
        queryParameters: (query == null || query.isEmpty) ? null : query,
      );

  Future<JsonResponse> getJson(String path,
      {Map<String, String>? query, Duration timeout = const Duration(seconds: 10)}) async {
    final req = await raw.getUrl(uri(path, query)).timeout(timeout);
    final res = await req.close().timeout(timeout);
    return JsonResponse(res.statusCode, await readJsonBody(res).timeout(timeout));
  }

  Future<JsonResponse> postJson(String path, Object? body,
      {Map<String, String>? query, Duration timeout = const Duration(seconds: 10)}) async {
    final req = await raw.postUrl(uri(path, query)).timeout(timeout);
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      req.headers.contentType = ContentType.json;
      req.contentLength = bytes.length;
      req.add(bytes);
    } else {
      req.contentLength = 0;
    }
    final res = await req.close().timeout(timeout);
    return JsonResponse(res.statusCode, await readJsonBody(res).timeout(timeout));
  }

  void close() => raw.close(force: true);

  /// [expectedId] null accepts any certificate (used only by [fetchInfo], which checks it afterwards).
  static HttpClient createPinnedClient(String? expectedId, Duration connectTimeout) {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = connectTimeout
      ..idleTimeout = const Duration(seconds: 15);
    client.badCertificateCallback =
        (cert, host, port) => expectedId == null || fingerprintOfDer(cert.der) == expectedId;
    return client;
  }

  /// Reads `/info` and accepts it only if the TLS certificate matches the claimed ID.
  static Future<DeviceInfo?> fetchInfo(String ip, int port,
      {String? expectedId, Duration timeout = const Duration(seconds: 3)}) async {
    final client = createPinnedClient(expectedId, timeout);
    try {
      final req = await client
          .getUrl(Uri(scheme: 'https', host: ip, port: port, path: '$kApiBase/info'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final cert = res.certificate;
      final body = await readJsonBody(res).timeout(timeout);
      final info = DeviceInfo.fromJson(body).copyWith(ip: ip);
      if (cert == null || fingerprintOfDer(cert.der) != info.id) return null;
      if (expectedId != null && info.id != expectedId) return null;
      return info;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

String describeError(Object e) {
  if (e is HandshakeException || e is TlsException) {
    return 'Secure connection failed. The device identity may have changed.';
  }
  if (e is TimeoutException) return 'Timed out';
  if (e is SocketException) return 'Connection lost';
  if (e is HttpException) return e.message;
  return e.toString();
}
