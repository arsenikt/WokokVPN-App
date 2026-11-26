import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/profile.dart';
import '../core/recipes.dart';

class Settings {
  Settings({
    this.recipe = Recipe.smart,
    this.killSwitch = true,
    this.autoSwitch = true,
    this.biometric = false,
    this.autoConnect = false,
    this.selectedDomains = const [],
    this.activeProfileId,
    this.fullTunnel = false,
    this.blockedDomains = const [],
    this.shield = true,
    this.shieldDomains = const [],
  });

  Recipe recipe;
  bool killSwitch;
  bool autoSwitch;
  bool biometric;
  bool autoConnect;
  bool fullTunnel; // desktop: TUN instead of system proxy (needs admin)
  List<String> selectedDomains;
  String? activeProfileId;
  List<String> blockedDomains; // Spy Check "lid"
  bool shield; // Guard blocks scam sites while the VPN is on
  List<String> shieldDomains;
}

/// Profiles live in secure storage (they contain keys); plain settings in prefs.
class Store {
  Store(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  static const _kProfiles = 'profiles.v1';

  static Future<Store> open() async => Store(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );

  Future<List<Profile>> loadProfiles() async {
    final raw = await _secure.read(key: _kProfiles);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Profile.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProfiles(List<Profile> list) => _secure.write(
      key: _kProfiles, value: jsonEncode(list.map((e) => e.toJson()).toList()));

  Settings loadSettings() {
    final s = Settings();
    s.recipe = Recipe.values.firstWhere(
      (r) => r.name == _prefs.getString('recipe'),
      orElse: () => Recipe.smart,
    );
    s.killSwitch = _prefs.getBool('killSwitch') ?? true;
    s.autoSwitch = _prefs.getBool('autoSwitch') ?? true;
    s.biometric = _prefs.getBool('biometric') ?? false;
    s.autoConnect = _prefs.getBool('autoConnect') ?? false;
    s.fullTunnel = _prefs.getBool('fullTunnel') ?? false;
    s.selectedDomains = _prefs.getStringList('selectedDomains') ?? [];
    s.activeProfileId = _prefs.getString('activeProfileId');
    s.blockedDomains = _prefs.getStringList('blockedDomains') ?? [];
    s.shield = _prefs.getBool('shield') ?? true;
    s.shieldDomains = _prefs.getStringList('shieldDomains') ?? [];
    return s;
  }

  Future<void> saveSettings(Settings s) async {
    await _prefs.setString('recipe', s.recipe.name);
    await _prefs.setBool('killSwitch', s.killSwitch);
    await _prefs.setBool('autoSwitch', s.autoSwitch);
    await _prefs.setBool('biometric', s.biometric);
    await _prefs.setBool('autoConnect', s.autoConnect);
    await _prefs.setBool('fullTunnel', s.fullTunnel);
    await _prefs.setStringList('selectedDomains', s.selectedDomains);
    await _prefs.setStringList('blockedDomains', s.blockedDomains);
    await _prefs.setBool('shield', s.shield);
    await _prefs.setStringList('shieldDomains', s.shieldDomains);
    if (s.activeProfileId == null) {
      await _prefs.remove('activeProfileId');
    } else {
      await _prefs.setString('activeProfileId', s.activeProfileId!);
    }
  }

  /// "Extinguish": wipe every key, profile and setting from the device.
  Future<void> wipeAll() async {
    await _secure.deleteAll();
    await _prefs.clear();
  }
}
