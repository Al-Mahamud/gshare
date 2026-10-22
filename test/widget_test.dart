import 'package:flutter_test/flutter_test.dart';
import 'package:gshare/core/identity.dart';
import 'package:gshare/core/models.dart';
import 'package:gshare/core/util.dart';
import 'package:gshare/platform/native_bridge.dart';

void main() {
  test('verification code is the same on both sides', () {
    const a = 'aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44';
    const b = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final code = verificationCode(a, b);
    expect(code, verificationCode(b, a));
    expect(code, matches(RegExp(r'^\d{3} \d{3}$')));
  });

  test('peer file names cannot escape the receive folder', () {
    expect(sanitizeFileName('../../etc/passwd'), 'passwd');
    expect(sanitizeFileName(r'C:\Users\me\photo.jpg'), 'photo.jpg');
    expect(sanitizeFileName('..'), 'file');
    expect(sanitizeFileName('a:b?.txt'), 'a_b_.txt');
  });

  test('item ids are validated', () {
    expect(isSafeId('a1b2c3d4'), isTrue);
    expect(isSafeId('../x'), isFalse);
    expect(isSafeId(''), isFalse);
  });

  test('wifi QR escapes special characters', () {
    const info = HotspotInfo(ssid: 'My;Net', password: r'p:a\ss');
    expect(info.wifiQr, r'WIFI:T:WPA;S:My\;Net;P:p\:a\\ss;;');
  });

  test('transfer item json round-trip', () {
    final item = TransferItem.text('hello');
    final back = TransferItem.fromJson(item.toJson());
    expect(back.kind, ItemKind.text);
    expect(back.text, 'hello');
    expect(back.size, 5);
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(50 * 1024 * 1024), '50 MB');
  });
}
