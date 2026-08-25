// lib/models/login_model.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginModel {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ========== التحقق من الاتصال ==========
  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ========== حفظ الجلسة محلياً ==========
  Future<void> saveSessionLocally(String userId, String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('user_id', userId);
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_email', email);
      await prefs.setString('login_time', DateTime.now().toIso8601String());

      Map<String, dynamic> sessionData = {
        'userId': userId,
        'email': email,
        'loginTime': DateTime.now().toIso8601String(),
      };
      await prefs.setString('logged_in_user', jsonEncode(sessionData));
    } catch (e) {
      print('خطأ في حفظ الجلسة: $e');
      rethrow;
    }
  }

  // ========== حفظ محاولة تسجيل الدخول عند عدم الاتصال ==========
  Future<void> saveOfflineLoginAttempt(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> pendingLogins = prefs.getStringList('pending_logins') ?? [];

      Map<String, dynamic> loginData = {
        'email': email,
        'password': password,
        'timestamp': DateTime.now().toIso8601String(),
      };

      pendingLogins.add(jsonEncode(loginData));
      await prefs.setStringList('pending_logins', pendingLogins);
    } catch (e) {
      print('خطأ في حفظ محاولة تسجيل الدخول: $e');
      rethrow;
    }
  }

  // ========== الحصول على محاولات تسجيل الدخول المعلقة ==========
  Future<List<Map<String, dynamic>>> getPendingLogins() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingLogins = prefs.getStringList('pending_logins') ?? [];
    List<Map<String, dynamic>> result = [];
    for (String jsonString in pendingLogins) {
      try {
        result.add(jsonDecode(jsonString));
      } catch (_) {}
    }
    return result;
  }

  // ========== مسح محاولات تسجيل الدخول المعلقة ==========
  Future<void> clearPendingLogins() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_logins');
  }

  // ========== تسجيل الدخول إلى Firebase ==========
  Future<User?> loginWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print("خطأ في تسجيل الدخول: ${e.message}");
      return null;
    } catch (e) {
      print("خطأ غير متوقع: $e");
      return null;
    }
  }
}