// lib/features/auth/data/datasources/auth_local_datasource.dart
// المسؤول الوحيد عن حفظ/استرجاع بيانات الجلسة ومحاولات تسجيل الدخول
// المعلّقة في SharedPreferences — منقول حرفياً من LoginModel القديم.
import 'dart:convert';

import 'package:fkra/core/constants/app_constants.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthLocalDataSource {
  AuthLocalDataSource._();
  static final AuthLocalDataSource instance = AuthLocalDataSource._();

  Future<void> saveSessionLocally(String userId, String email) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(PrefKeys.userId, userId);
    await prefs.setBool(PrefKeys.isLoggedIn, true);
    await prefs.setString(PrefKeys.userEmail, email);
    await prefs.setString(PrefKeys.loginTime, DateTime.now().toIso8601String());

    Map<String, dynamic> sessionData = {
      'userId': userId,
      'email': email,
      'loginTime': DateTime.now().toIso8601String(),
    };
    await prefs.setString(PrefKeys.loggedInUser, jsonEncode(sessionData));
  }

  Future<void> saveOfflineLoginAttempt(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> pendingLogins = prefs.getStringList(PrefKeys.pendingLogins) ?? [];

    Map<String, dynamic> loginData = {
      'email': email,
      'password': password,
      'timestamp': DateTime.now().toIso8601String(),
    };

    pendingLogins.add(jsonEncode(loginData));
    await prefs.setStringList(PrefKeys.pendingLogins, pendingLogins);
  }

  Future<List<Map<String, dynamic>>> getPendingLogins() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingLogins = prefs.getStringList(PrefKeys.pendingLogins) ?? [];
    List<Map<String, dynamic>> result = [];
    for (String jsonString in pendingLogins) {
      try {
        result.add(jsonDecode(jsonString));
      } catch (_) {}
    }
    return result;
  }

  Future<void> clearPendingLogins() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.pendingLogins);
  }

  Future<void> savePendingLogins(List<Map<String, dynamic>> logs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      PrefKeys.pendingLogins,
      logs.map((l) => jsonEncode(l)).toList(),
    );
  }

  /// مسح بيانات الجلسة المحفوظة محلياً حتى لا يعيد التطبيق فتح الجلسة القديمة
  /// ويسمح بتسجيل الدخول بحساب آخر (Gmail أو غيره).
  Future<void> clearSessionPrefs() async {
    try {
      await MemberSessionService.instance.clearSession();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefKeys.userId);
      await prefs.remove(PrefKeys.isLoggedIn);
      await prefs.remove(PrefKeys.userEmail);
      await prefs.remove(PrefKeys.loginTime);
      await prefs.remove(PrefKeys.loggedInUser);
    } catch (_) {
      // لا نوقف تسجيل الخروج بسبب فشل مسح الجلسة.
    }
  }
}