import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static final LanguageService _instance = LanguageService._internal();
  factory LanguageService() => _instance;
  LanguageService._internal();

  final ValueNotifier<String> currentLocale = ValueNotifier<String>('ar');
  static const String _langKey = 'user_language';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString(_langKey);
    if (savedLang != null) {
      currentLocale.value = savedLang;
    }
  }

  Future<void> changeLanguage(String langCode) async {
    if (currentLocale.value == langCode) return;

    currentLocale.value = langCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, langCode);
  }

  bool get isArabic => currentLocale.value == 'ar';
}
