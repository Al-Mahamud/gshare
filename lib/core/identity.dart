import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart' show CryptoUtils, X509Utils;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// This device's TLS identity. The certificate fingerprint is the device ID.
class Identity {
  Identity._(this.certPem, this.keyPem) : fingerprint = fingerprintOfDer(pemToDer(certPem));

  final String certPem;
  final String keyPem;
  final String fingerprint;

  static Future<Identity> loadOrCreate() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'identity'));
    final certFile = File(p.join(dir.path, 'cert.pem'));
    final keyFile = File(p.join(dir.path, 'key.pem'));

    if (await certFile.exists() && await keyFile.exists()) {
      return Identity._(await certFile.readAsString(), await keyFile.readAsString());
    }

    // RSA key generation in pure Dart takes a few seconds.
    final generated = await Isolate.run<List<String>>(_generateIdentity);
    await dir.create(recursive: true);
    await keyFile.writeAsString(generated[1], flush: true);
    await certFile.writeAsString(generated[0], flush: true);
    return Identity._(generated[0], generated[1]);
  }

  SecurityContext serverContext() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));
}

List<String> _generateIdentity() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final dynamic privateKey = pair.privateKey;
  final dynamic publicKey = pair.publicKey;
  final csr = X509Utils.generateRsaCsrPem({'CN': 'gshare', 'O': 'gshare'}, privateKey, publicKey);
  final cert = X509Utils.generateSelfSignedCertificate(pair.privateKey, csr, 3650);
  final key = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
  return [cert, key];
}

List<int> pemToDer(String pem) {
  final body = pem
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return base64.decode(body);
}

String fingerprintOfDer(List<int> der) => sha256.convert(der).toString();

/// Six-digit code both devices show so users can compare them.
String verificationCode(String idA, String idB) {
  final ids = [idA, idB]..sort();
  final d = sha256.convert(utf8.encode(ids.join(':'))).bytes;
  final n = ((d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3]) & 0x7fffffff;
  final s = (n % 1000000).toString().padLeft(6, '0');
  return '${s.substring(0, 3)} ${s.substring(3)}';
}

/// "ab12 cd34 ..." for display.
String groupHex(String hex, {int group = 4}) {
  final sb = StringBuffer();
  for (var i = 0; i < hex.length; i += group) {
    if (i > 0) sb.write(' ');
    sb.write(hex.substring(i, i + group > hex.length ? hex.length : i + group));
  }
  return sb.toString();
}
