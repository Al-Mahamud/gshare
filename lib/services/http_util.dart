import 'dart:convert';
import 'dart:io';

Future<void> sendJson(HttpResponse res, int status, Object body) async {
  res.statusCode = status;
  // Error replies may come before the request body was read; don't reuse that connection.
  if (status >= 400) res.persistentConnection = false;
  res.headers.contentType = ContentType.json;
  res.write(jsonEncode(body));
  await res.close();
}
