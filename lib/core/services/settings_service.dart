import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  ThemeMode _themeMode = ThemeMode.dark;
  bool _amoledBlack = true;
  bool _liquidGlass = true;
  bool _dynamicAccent = true;
  Color _seedColor = const Color(0xFF00E5FF);
  int _minTrackSeconds = 10;
  bool _gapless = true;
  bool _bitPerfectUsbDac = false;
  Set<String> _enabledExtensions = {'morning_mix', 'mornye_sflx'};
  List<String> _sflxSources = [];

  ThemeMode get themeMode => _themeMode;
  bool get amoledBlack => _amoledBlack;
  bool get liquidGlass => _liquidGlass;
  bool get dynamicAccent => _dynamicAccent;
  Color get seedColor => _seedColor;
  int get minTrackSeconds => _minTrackSeconds;
  bool get gapless => _gapless;
  bool get bitPerfectUsbDac => _bitPerfectUsbDac;
  Set<String> get enabledExtensions => Set.unmodifiable(_enabledExtensions);
  List<String> get sflxSources => List.unmodifiable(_sflxSources);

  void _load() {
    final modeIdx = _prefs.getInt('nami.themeMode') ?? ThemeMode.dark.index;
    _themeMode = ThemeMode.values[modeIdx.clamp(0, ThemeMode.values.length - 1)];
    _amoledBlack = _prefs.getBool('nami.amoledBlack') ?? true;
    _liquidGlass = _prefs.getBool('nami.liquidGlass') ?? true;
    _dynamicAccent = _prefs.getBool('nami.dynamicAccent') ?? true;
    _seedColor = Color(_prefs.getInt('nami.seedColor') ?? 0xFF00E5FF);
    _minTrackSeconds = _prefs.getInt('nami.minTrackSeconds') ?? 10;
    _gapless = _prefs.getBool('nami.gapless') ?? true;
    _bitPerfectUsbDac = _prefs.getBool('nami.bitPerfectUsbDac') ?? false;
    final ext = _prefs.getStringList('nami.enabledExtensions');
    if (ext != null) _enabledExtensions = ext.toSet();
    _sflxSources = _prefs.getStringList('nami.sflxSources') ?? [];
  }

  Future<void> setAmoledBlack(bool value) async {
    _amoledBlack = value;
    notifyListeners();
    await _prefs.setBool('nami.amoledBlack', value);
  }

  Future<void> setLiquidGlass(bool value) async {
    _liquidGlass = value;
    notifyListeners();
    await _prefs.setBool('nami.liquidGlass', value);
  }

  Future<void> setDynamicAccent(bool value) async {
    _dynamicAccent = value;
    notifyListeners();
    await _prefs.setBool('nami.dynamicAccent', value);
  }

  Future<void> setBitPerfectUsbDac(bool value) async {
    _bitPerfectUsbDac = value;
    notifyListeners();
    await _prefs.setBool('nami.bitPerfectUsbDac', value);
  }

  Future<void> setExtensionEnabled(String id, bool enabled) async {
    if (enabled) {
      _enabledExtensions.add(id);
    } else {
      _enabledExtensions.remove(id);
    }
    notifyListeners();
    await _prefs.setStringList('nami.enabledExtensions', _enabledExtensions.toList());
  }

  Future<void> addSflxSource(String jsonConfig) async {
    _sflxSources.add(jsonConfig);
    notifyListeners();
    await _prefs.setStringList('nami.sflxSources', _sflxSources);
  }

  Future<void> removeSflxSourceAt(int index) async {
    if (index < 0 || index >= _sflxSources.length) return;
    _sflxSources.removeAt(index);
    notifyListeners();
    await _prefs.setStringList('nami.sflxSources', _sflxSources);
  }
}
