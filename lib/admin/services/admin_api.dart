// lib/admin/services/admin_api.dart
// استدعاء Cloud Functions لإجراء العمليات الآمنة (تخضع لتفويض الخادم).
import 'package:cloud_functions/cloud_functions.dart';

class AdminApi {
  AdminApi._();
  static final AdminApi instance = AdminApi._();

  final FirebaseFunctions _func = FirebaseFunctions.instance;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _func.httpsCallable(name).call(data);
      return (res.data as Map?)?.cast<String, dynamic>() ?? {};
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        throw 'خدمة الخادم ($name) غير منشورة على فيربيز حالياً (Cloud Function غير متوفرة).';
      }
      throw e.message ?? e.code;
    } catch (e) {
      final s = e.toString();
      if (s.contains('not-found') || s.contains('NOT_FOUND')) {
        throw 'خدمة الخادم ($name) غير منشورة على فيربيز حالياً (Cloud Function غير متوفرة).';
      }
      throw s;
    }
  }

  /// يعيِّن/يعدّل دور مدير (يتطلب Super Admin على الخادم).
  Future<void> setAdminRole({
    required String uid,
    required String role,
    String? email,
    String? displayName,
  }) async {
    await _call('setAdminRole', {
      'uid': uid,
      'role': role,
      if (email != null) 'email': email,
      if (displayName != null) 'displayName': displayName,
    });
  }

  /// يزيل دور مدير (يتطلب Super Admin على الخادم).
  Future<void> removeAdminRole({required String uid}) async {
    await _call('removeAdminRole', {'uid': uid});
  }

  /// تحديث يدوي للإحصائيات المجمّعة.
  Future<Map<String, dynamic>> refreshStats() async {
    return _call('refreshStats', {});
  }

  /// إحصاءات مستخدم محدد (يتطلب admin/super).
  Future<Map<String, dynamic>> getUserStats({required String uid}) async {
    return _call('getUserStats', {'uid': uid});
  }

  /// تحديث إعدادات المنصة (يتطلب Super Admin على الخادم).
  Future<Map<String, dynamic>> updateAppConfig(Map<String, dynamic> patch) async {
    return _call('updateAppConfig', patch);
  }

  /// حذف حساب مستخدم نهائياً (يتطلب Super Admin + Cloud Function منشورة).
  Future<void> deleteUser({required String uid}) async {
    await _call('deleteUser', {'uid': uid});
  }

  /// تعطيل/تفعيل حساب مستخدم على مستوى Firebase Auth (يتطلب Cloud Function).
  Future<void> setUserStatus({required String uid, required bool disabled}) async {
    await _call('setUserStatus', {'uid': uid, 'disabled': disabled});
  }

  /// بيانات الاستهلاك الرسمية من Google Cloud Monitoring
  /// (قراءات/كتابات/حذف + عدد مستخدمي Auth).
  Future<Map<String, dynamic>> getFirebaseUsage({int days = 7}) async {
    return _call('getFirebaseUsage', {'days': days});
  }
}