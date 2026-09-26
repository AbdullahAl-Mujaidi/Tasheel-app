// lib/services/analytics_service.dart
// خدمة تحليلات Firebase Analytics لإرسال أحداث التطبيق وقياس نشاط المستخدمين.

import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// المراقب التلقائي للتنقل بين الشاشات
  FirebaseAnalyticsObserver get observer => FirebaseAnalyticsObserver(analytics: _analytics);

  /// تسجيل دخول المستخدم
  Future<void> logLogin({required String method}) async {
    try {
      await _analytics.logLogin(loginMethod: method);
    } catch (e) {
      // لا نُعطل التطبيق عند فشل التحليلات
    }
  }

  /// تسجيل حساب جديد
  Future<void> logSignUp({required String method}) async {
    try {
      await _analytics.logSignUp(signUpMethod: method);
    } catch (_) {}
  }

  /// إضافة مشروع / عمل جديد
  Future<void> logBusinessCreated() async {
    try {
      await _analytics.logEvent(name: 'business_created');
    } catch (_) {}
  }

  /// تعديل عمل
  Future<void> logBusinessUpdated() async {
    try {
      await _analytics.logEvent(name: 'business_updated');
    } catch (_) {}
  }

  /// حذف عمل
  Future<void> logBusinessDeleted() async {
    try {
      await _analytics.logEvent(name: 'business_deleted');
    } catch (_) {}
  }

  /// إضافة مصروف
  Future<void> logExpenseAdded() async {
    try {
      await _analytics.logEvent(name: 'expense_added');
    } catch (_) {}
  }

  /// إضافة عامل
  Future<void> logWorkerAdded() async {
    try {
      await _analytics.logEvent(name: 'worker_added');
    } catch (_) {}
  }

  /// إنشاء تقرير
  Future<void> logReportGenerated({required String type}) async {
    try {
      await _analytics.logEvent(
        name: 'report_generated',
        parameters: {'report_type': type},
      );
    } catch (_) {}
  }

  /// مزامنة البيانات
  Future<void> logDataSynced() async {
    try {
      await _analytics.logEvent(name: 'data_synced');
    } catch (_) {}
  }

  /// تسجيل زيارة شاشة معينة
  Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (_) {}
  }
}
