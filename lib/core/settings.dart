import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static const _kName = 'deviceName';
  static const _kNameChosen = 'deviceNameChosen';
  static const _kAutoAccept = 'autoAcceptTrusted';
  static const _kGallery = 'saveMediaToGallery';
  static const _kTrusted = 'trustedDevices';

  late String _deviceName;
  late bool _nameChosen;
  late bool _autoAcceptTrusted;
  late bool _saveMediaToGallery;
  final Map<String, String> _trusted = {};

  static Future<AppSettings> load() async {
    final s = AppSettings._(await SharedPreferences.getInstance());
    await s._read();
    return s;
  }

  Future<void> _read() async {
    final name = _prefs.getString(_kName);
    if (name == null || name.trim().isEmpty) {
      _deviceName = '${DevicePlatform.current.label} ${1000 + Random().nextInt(9000)}';
      await _prefs.setString(_kName, _deviceName);
    } else {
      _deviceName = name;
    }
    _nameChosen = _prefs.getBool(_kNameChosen) ?? false;
    _autoAcceptTrusted = _prefs.getBool(_kAutoAccept) ?? true;
    _saveMediaToGallery = _prefs.getBool(_kGallery) ?? true;
    final raw = _prefs.getString(_kTrusted);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _trusted.addAll(map.map((k, v) => MapEntry(k, v as String)));
      } catch (_) {}
    }
  }

  String get deviceName => _deviceName;

  /// False until the user has typed a name on first launch; until then [deviceName] is a placeholder.
  bool get hasChosenName => _nameChosen;
  bool get autoAcceptTrusted => _autoAcceptTrusted;
  bool get saveMediaToGallery => _saveMediaToGallery;
  Map<String, String> get trusted => Map.unmodifiable(_trusted);

  bool isTrusted(String id) => _trusted.containsKey(id);

  Future<void> setDeviceName(String value) async {
    final v = value.trim();
    if (v.isEmpty || (_nameChosen && v == _deviceName)) return;
    _deviceName = v.length > 40 ? v.substring(0, 40) : v;
    _nameChosen = true;
    await _prefs.setString(_kName, _deviceName);
    await _prefs.setBool(_kNameChosen, true);
    notifyListeners();
  }

  Future<void> setAutoAcceptTrusted(bool value) async {
    _autoAcceptTrusted = value;
    await _prefs.setBool(_kAutoAccept, value);
    notifyListeners();
  }

  Future<void> setSaveMediaToGallery(bool value) async {
    _saveMediaToGallery = value;
    await _prefs.setBool(_kGallery, value);
    notifyListeners();
  }

  Future<void> trust(String id, String name) async {
    _trusted[id] = name;
    await _saveTrusted();
  }

  Future<void> untrust(String id) async {
    _trusted.remove(id);
    await _saveTrusted();
  }

  Future<void> _saveTrusted() async {
    await _prefs.setString(_kTrusted, jsonEncode(_trusted));
    notifyListeners();
  }
}
