import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _fontSizeKey = 'app_font_size_multiplier';
  final ValueNotifier<double> fontSizeMultiplier = ValueNotifier<double>(1.0);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    fontSizeMultiplier.value = prefs.getDouble(_fontSizeKey) ?? 1.0;
  }

  Future<void> setFontSize(double multiplier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, multiplier);
    fontSizeMultiplier.value = multiplier;
  }
}
