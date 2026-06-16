import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController _instance = ThemeController._internal();
  factory ThemeController() => _instance;
  ThemeController._internal();

  static const String _themeKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);

    if (savedTheme != null) {
      switch (savedTheme) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        case 'system':
        default:
          _themeMode = ThemeMode.system;
      }
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode newMode) async {
    if (newMode == _themeMode) return;

    _themeMode = newMode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    String modeString = 'system';
    if (newMode == ThemeMode.light) modeString = 'light';
    if (newMode == ThemeMode.dark) modeString = 'dark';
    
    await prefs.setString(_themeKey, modeString);
  }
}
