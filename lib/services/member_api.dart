// lib/services/member_api.dart
// استدعاء Cloud Functions الخاصة بإدارة المستخدمين التابعين.
// جميع العمليات الحساسة (إنشاء حسابات Auth، تعطيلها، حذفها) تتم على الخادم
// عبر Admin SDK ولا تمر أبداً من التطبيق مباشرة إلى Firebase Auth.
//
// عند عدم توفر الدوال (الخطة المجانية Spark أو خلل نشر مؤقت) يرتد التطبيق
// تلقائياً إلى MemberApiFallback الذي ينفذ نفس العمليات من العميل مباشرة
// مع بقاء كل قواعد الأمان على Firestore كما هي.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/services/member_api_fallback.dart';

/// يرمى عندما تكون Cloud Function غير منشورة/غير متاحة في الوقت الحالي —
/// يستدعي ذلك الارتداد التلقائي إلى البديل المباشر.
class _FunctionUnavailableException implements Exception {
  final String message;
  _FunctionUnavailableException(this.message);
  @override
  String toString() => message;
}

class MemberApi {
  MemberApi._();
  static final MemberApi instance = MemberApi._();

  final FirebaseFunctions _func = FirebaseFunctions.instance;
  final MemberApiFallback _fallback = MemberApiFallback.instance;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _func.httpsCallable(name).call(data);
      return (res.data as Map?)?.cast<String, dynamic>() ?? {};
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(name, e.code, e.message);
    } catch (e) {
      final s = e.toString();
      if (s.contains('not-found') ||
          s.contains('NOT_FOUND') ||
          s.contains('404') ||
          s.contains('response-error')) {
        throw _FunctionUnavailableException(
            'خدمة الخادم ($name) غير منشورة حالياً.');
      }
      throw 'حدث خطأ في الاتصال بالخادم، حاول مرة أخرى.';
    }
  }

  /// تحويل أخطاء Cloud Functions إلى رسائل عربية واضحة دون كشف أخطاء Firebase الخام.
  String _mapError(String name, String code, String? message) {
    final c = code.toLowerCase();
    // الدوال غير منشورة/غير متاحة (كل صيغ SDK الممكنة): الارتداد إلى البديل
    // المباشر فوراً بدل خطأ صامت يمنع إنشاء الحساب أو الدعوة.
    if (c == 'not-found' || c == 'not_found' || c == 'response-error') {
      throw _FunctionUnavailableException(
          'خدمة الخادم ($name) غير منشورة حالياً.');
    }
    switch (c) {
      case 'unauthenticated':
        return 'يرجى تسجيل الدخول أولاً';
      case 'permission-denied':
        return 'لا تملك صلاحية تنفيذ هذه العملية';
      case 'already-exists':
        return 'البريد مستخدم بالفعل';
      case 'invalid-argument':
        return message ?? 'البيانات المدخلة غير صحيحة';
      default:
        return message ?? 'حدث خطأ أثناء تنفيذ العملية';
    }
  }

  /// إنشاء مستخدم تابع (يتطلب أن يكون المستدعي مالكاً وليس تابِعاً).
  Future<String> createSubUser({
    required String name,
    required String email,
    required String temporaryPassword,
    required Map<String, Map<String, bool>> permissions,
    Map<String, List<String>>? scopedIds,
  }) async {
    // حارس منع التفويض الذاتي: لا يمكن لصاحب الحساب تفويض نفسه بنفس بريده
    // (يغطي كل المداخل: شاشة المستخدمين، مشاركة عمل، مشاركة عامل).
    final selfEmail = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
    if (selfEmail != null && email.trim().toLowerCase() == selfEmail) {
      throw 'لا يمكن تفويض نفسك بنفس بريدك';
    }
    try {
      final result = await _call('createSubUser', {
        'name': name,
        'email': email,
        'temporaryPassword': temporaryPassword,
        'permissions': permissions,
        if (scopedIds != null && scopedIds.isNotEmpty) 'scopedIds': scopedIds,
      });
      return (result['uid'] ?? '').toString();
    } on _FunctionUnavailableException {
      return _fallback.createSubUser(
        name: name,
        email: email,
        temporaryPassword: temporaryPassword,
        permissions: permissions,
        scopedIds: scopedIds,
      );
    }
  }

  /// تعديل اسم/صلاحيات مستخدم تابع.
  Future<void> updateSubUser({
    required String ownerUid,
    required String memberUid,
    String? name,
    Map<String, Map<String, bool>>? permissions,
  }) async {
    try {
      await _call('updateSubUser', {
        'ownerUid': ownerUid,
        'memberUid': memberUid,
        if (name != null) 'name': name,
        if (permissions != null) 'permissions': permissions,
      });
    } on _FunctionUnavailableException {
      await _fallback.updateSubUser(
        ownerUid: ownerUid,
        memberUid: memberUid,
        name: name,
        permissions: permissions,
      );
    }
  }

  /// تعطيل/تفعيل مستخدم تابع.
  Future<void> setSubUserStatus({
    required String ownerUid,
    required String memberUid,
    required bool disabled,
  }) async {
    try {
      await _call('setSubUserStatus', {
        'ownerUid': ownerUid,
        'memberUid': memberUid,
        'disabled': disabled,
      });
    } on _FunctionUnavailableException {
      await _fallback.setSubUserStatus(
        ownerUid: ownerUid,
        memberUid: memberUid,
        disabled: disabled,
      );
    }
  }

  /// إعادة تعيين كلمة مرور مستخدم تابع. عند توفر الدوال تُولَّد كلمة مرور
  /// مؤقتة ويُجبر العضو على تغييرها؛ وعند عدم توفرها يُرسَل رابط استعادة
  /// للبريد. يعيد دائماً رسالة توضيحية لصاحب الحساب.
  Future<String> resetSubUserPassword({
    required String ownerUid,
    required String memberUid,
    required String temporaryPassword,
  }) async {
    try {
      await _call('resetSubUserPassword', {
        'ownerUid': ownerUid,
        'memberUid': memberUid,
        'temporaryPassword': temporaryPassword,
      });
      return 'تمت إعادة تعيين كلمة المرور المؤقتة: $temporaryPassword';
    } on _FunctionUnavailableException {
      return _fallback.resetSubUserPassword(
        ownerUid: ownerUid,
        memberUid: memberUid,
        temporaryPassword: temporaryPassword,
      );
    }
  }

  /// حذف مستخدم تابع نهائياً (حساب Auth + وثيقة العضوية).
  Future<void> deleteSubUser({
    required String ownerUid,
    required String memberUid,
  }) async {
    try {
      await _call('deleteSubUser', {
        'ownerUid': ownerUid,
        'memberUid': memberUid,
      });
    } on _FunctionUnavailableException {
      await _fallback.deleteSubUser(
        ownerUid: ownerUid,
        memberUid: memberUid,
      );
    }
  }
}