// lib/services/fcm_token_service.dart
// تسجيل أجهزة المستخدم في Firestore لتمكين إرسال الإشعارات عبر Cloud Functions.
// الجديد فقط: يخزن معرف الجهاز تحت users/{uid}/devices (قواعد Firestore تمنع
// أي قارئ خارجي إلا المالك نفسه).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:flutter/foundation.dart';

class FcmTokenService {
  static FirebaseMessaging? _messaging;

  static bool _supported() {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  /// يُستدعى مرة واحدة عند تشغيل التطبيق.
  static Future<void> init() async {
    if (!_supported()) return;
    try {
      _messaging = FirebaseMessaging.instance;
      await _messaging!.requestPermission(alert: true, badge: true, sound: true);

      // تحديث الـ token عند التجديد
      _messaging!.onTokenRefresh.listen((token) {
        _storeToken(token);
      });

      final String? token = await _messaging!.getToken();
      if (token != null) await _storeToken(token);

      // تسجيل الـ token مرة أخرى عند دخول مستخدم (بعد تغيير الجلسة)
      FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user != null) {
          await Future<void>.delayed(const Duration(seconds: 1));
          final String? t = await _messaging?.getToken();
          if (t != null) await _storeToken(t);
        }
      });
    } catch (e) {
      // تعطّل FCM يجب ألا يكسر التطبيق
      // ignore: avoid_print
      print('تعذّر تهيئة الإشعارات: $e');
    }
  }

  static Future<void> _storeToken(String token) async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(token)
          .set({
        'token': token,
        'platform': _platformName(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      FirebaseUsageTracker.instance.recordWrite();
    } catch (e) {
      // ignore: avoid_print
      print('فشل حفظ token: $e');
    }
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      default:
        return 'other';
    }
  }
}