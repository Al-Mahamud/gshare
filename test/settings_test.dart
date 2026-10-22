import 'package:flutter_test/flutter_test.dart';
import 'package:gshare/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh install has no chosen name, only a placeholder', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.hasChosenName, isFalse);
    expect(s.deviceName, isNotEmpty);
  });

  test('setting a name marks it chosen and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    await s.setDeviceName('  Rahim  ');
    expect(s.hasChosenName, isTrue);
    expect(s.deviceName, 'Rahim');

    final reloaded = await AppSettings.load();
    expect(reloaded.hasChosenName, isTrue);
    expect(reloaded.deviceName, 'Rahim');
  });

  test('keeping the placeholder name still counts as choosing it', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    await s.setDeviceName(s.deviceName);
    expect(s.hasChosenName, isTrue);
  });

  test('blank names are ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    await s.setDeviceName('   ');
    expect(s.hasChosenName, isFalse);
  });

  test('existing installs from before this setting are asked once', () async {
    SharedPreferences.setMockInitialValues({'deviceName': 'Android 4821'});
    final s = await AppSettings.load();
    expect(s.hasChosenName, isFalse);
    expect(s.deviceName, 'Android 4821');
  });
}
