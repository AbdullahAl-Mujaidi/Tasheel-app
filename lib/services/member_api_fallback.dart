// ignore_for_file: avoid_print
// lib/services/member_api_fallback.dart
// البديل المباشر من العميل (يعمل على الخطة المجانية Spark دون Cloud Functions).
//
// لماذا يوجد هذا البديل؟
//  - إنشاء حساب في Firebase Auth (مستخدِم تابع) يتطلب الخادم عادةً (Admin SDK).
//  - على الخطة المجانية لا يمكن نشر Cloud Functions، لذا نُنشئ الحساب عبر
//    REST (identitytoolkit) بمفتاح المشروع العام (آمن: هو مفتاح العميل نفسه
//    الذي تستخدمه شاشة التسجيل أصلاً)، ثُم نكتب وثيقة العضوية مباشرة في
//    Firestore (المالك يملك صلاحية الكتابة في users/{ownerUid}/team_members).
//  - العمليات التي تتطلب Admin SDK فقط (تعطيل/حذف حساب Auth) تُنفَّذ على
//    مستوى البيانات: وضع status = disabled/deleted في وثيقة العضوية، وقواعد
//    الأمان (memberDocActive) تحجب بيانات المالك عنه فوراً، والتطبيق يمنعه
//    من الدخول عند فحص الحالة في شاشات الدخول.
//  - إعادة تعيين كلمة المرور (بدون Admin SDK) تُرسل رابط استعادة عبر البريد
//    للمستخدِم نفسه (PASSWORD_RESET OOB).
//
// متى يُستخدم؟ فقط عندما تكون Cloud Function غير منشورة/غير متاحة. وعند
// ترقية المشروع لاحقاً ونشر الدوال، يعود التطبيق تلقائياً للمسار الملكي.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/firebase_options.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:http/http.dart' as http;

class MemberApiFallback {
  MemberApiFallback._();
  static final MemberApiFallback instance = MemberApiFallback._();

  final TeamMemberRepository _repo = TeamMemberRepository();

  static const String _authBase = 'https://identitytoolkit.googleapis.com/v1';

  String get _apiKey => DefaultFirebaseOptions.currentPlatform.apiKey;

  Future<String> _currentOwnerUid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw 'يرجى تسجيل الدخول أولاً';
    }
    return user.uid;
  }

  /// إنشاء مستخدم تابع: حساب Auth عبر REST + وثيقة عضوية في Firestore.
  /// يعيد uid الحساب الجديد.
  Future<String> createSubUser({
    required String name,
    required String email,
    required String temporaryPassword,
    required Map<String, Map<String, bool>> permissions,
    Map<String, List<String>>? scopedIds,
  }) async {
    final selfEmail = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
    if (selfEmail != null && email.trim().toLowerCase() == selfEmail) {
      throw 'لا يمكن تفويض نفسك بنفس بريدك';
    }
    final ownerUid = await _currentOwnerUid();
    final body = jsonEncode({
      'email': email.trim(),
      'password': temporaryPassword,
      'returnSecureToken': true,
    });
    final res = await http.post(
      Uri.parse('$_authBase/accounts:signUp?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (res.statusCode != 200) {
      final message = _extractRpcError(res.body);
      if (message.contains('EMAIL_EXISTS') || message.contains('email-exists')) {
        // البريد مسجّل مسبقاً بحساب خاص بالعضو: لا يمكن إنشاء حساب آخر، ولا
        // يستطيع العميل كشف UID الحساب الموجود — لذا تُكتب "دعوة تفويض"
        // تُفعَّل تلقائياً عند أول تسجيل دخول لصاحب البريد بحسابه.
        final ownerName = FirebaseAuth.instance.currentUser?.displayName ?? '';
        await _repo.createInvite(
          ownerUid: ownerUid,
          ownerName: ownerName,
          name: name.trim(),
          email: email.trim(),
          permissions: _normalizePermissions(permissions),
          scopedIds: scopedIds,
        );
        print('createSubUser: EMAIL_EXISTS → دعوة تفويض لـ ${email.trim()} تحت المالك $ownerUid');
        throw MemberInviteSentException(
            'البريد مسجّل مسبقاً بحساب خاص بالعضو. تم إرسال تفويض له وسيُفعَّل '
            'فور تسجيل دخوله بحسابه الحالي.');
      }
      if (message.contains('INVALID_EMAIL')) {
        throw 'البريد الإلكتروني غير صالح';
      }
      if (message.contains('WEAK_PASSWORD')) {
        throw 'كلمة المرور ضعيفة (6 أحرف على الأقل مع حرف كبير ورقم)';
      }
      throw 'تعذّر إنشاء الحساب (الخطة المجانية): ${_arabicRpc(message)}';
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final memberUid = (data['localId'] ?? '').toString();
    if (memberUid.isEmpty) {
      throw 'تعذّر إنشاء الحساب، حاول مرة أخرى';
    }

    await _writeMembershipDoc(
      ownerUid: ownerUid,
      memberUid: memberUid,
      name: name.trim(),
      email: email.trim(),
      permissions: permissions,
      status: 'active',
      mustChangePassword: true,
      scopedIds: scopedIds,
    );
    return memberUid;
  }

  /// تعديل اسم/صلاحيات عضو (بصمة: لا يمس ownerUid/status).
  Future<void> updateSubUser({
    required String ownerUid,
    required String memberUid,
    String? name,
    Map<String, Map<String, bool>>? permissions,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) data['name'] = name.trim();
    if (permissions != null) {
      data['permissions'] = _normalizePermissions(permissions);
    }
    await _ref(ownerUid, memberUid).update(data);
  }

  /// تعطيل/تفعيل (على مستوى البيانات: rules تحجب وصول بيانات المالك فوراً،
  /// والتطبيق يمنع الدخول عند التحقق من الحالة). لا يمكن تعطيل حساب Auth
  /// نفسه دون Admin SDK — يُزال هذا القيد تلقائياً بعد نشر الدوال.
  Future<void> setSubUserStatus({
    required String ownerUid,
    required String memberUid,
    required bool disabled,
  }) async {
    await _ref(ownerUid, memberUid).update({
      'status': disabled ? 'disabled' : 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// إعادة تعيين كلمة المرور على الخطة المجانية: إرسال رابط استعادة للبريد.
  /// يعيد رسالة عرض للمالك.
  Future<String> resetSubUserPassword({
    required String ownerUid,
    required String memberUid,
    required String temporaryPassword,
  }) async {
    final member = await _ref(ownerUid, memberUid).get();
    if (!member.exists) throw 'العضو غير موجود';
    final email =
        ((member.data() as Map<String, dynamic>?)?['email'] ?? '').toString();
    if (email.isEmpty) throw 'لا يوجد بريد لهذا العضو';
    final res = await http.post(
      Uri.parse('$_authBase/accounts:sendOobCode?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'requestType': 'PASSWORD_RESET', 'email': email}),
    );
    if (res.statusCode != 200) {
      final message = _extractRpcError(res.body);
      if (message.contains('EMAIL_NOT_FOUND')) {
        throw 'لم يُعثر على حساب لهذا البريد';
      }
      throw 'تعذّر إرسال رابط الاستعادة، حاول مرة أخرى';
    }
    return 'تم إرسال رابط إعادة تعيين كلمة المرور إلى بريد المستخدم';
  }

  /// حذف ناعم: يوضع status = deleted وقواعد الأمان تحجب بيانات المالك عنه،
  /// والتطبيق يمنعه من الدخول. (لا يمكن حذف حساب Auth دون Admin SDK —
  /// بعد رفع الخطة ونشر الدوال يُحذف الحساب فعلياً.)
  Future<void> deleteSubUser({
    required String ownerUid,
    required String memberUid,
  }) async {
    await _ref(ownerUid, memberUid).update({
      'status': 'deleted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==================== أدوات داخلية ====================

  DocumentReference _ref(String ownerUid, String memberUid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(ownerUid)
          .collection('team_members')
          .doc(memberUid);

  Future<void> _writeMembershipDoc({
    required String ownerUid,
    required String memberUid,
    required String name,
    required String email,
    required Map<String, Map<String, bool>> permissions,
    required String status,
    required bool mustChangePassword,
    Map<String, List<String>>? scopedIds,
  }) async {
    final ownerName = FirebaseAuth.instance.currentUser?.displayName ?? '';
    await _ref(ownerUid, memberUid).set({
      'uid': memberUid,
      'ownerUid': ownerUid,
      'name': name,
      'email': email,
      'role': 'employee',
      'permissions': _normalizePermissions(permissions),
      if (scopedIds != null && scopedIds.isNotEmpty) 'scopedIds': scopedIds,
      'status': status,
      'mustChangePassword': mustChangePassword,
      'ownerName': ownerName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // كتابة السجل السريع وثيقة المستخدم للبحث المباشر عند تسجيل الدخول
    try {
      await FirebaseFirestore.instance.collection('member_lookups').doc(memberUid).set({
        'uid': memberUid,
        'ownerUid': ownerUid,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('users').doc(memberUid).set({
        'uid': memberUid,
        'ownerUid': ownerUid,
        'userType': 'sub_user',
        'email': email,
        'fullName': name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('تحذير: تعذر كتابة سجل الربط: $e');
    }
    print('_writeMembershipDoc: عُضوية $memberUid تحت المالك $ownerUid '
        'scoped=${(scopedIds ?? {}).toString()}');
  }

  /// يوحد صيغة الصلاحيات بحيث تشمل كل الوحدات (لا تسقط مفاتيح أبداً —
  /// تطلبه قواعد memberCan عند الفحص).
  Map<String, Map<String, bool>> _normalizePermissions(
      Map<String, Map<String, bool>> permissions) {
    final map = <String, Map<String, bool>>{};
    for (final module in TeamPermissions.modules) {
      final src = permissions[module] ?? const <String, bool>{};
      final isFull =
          module != TeamPermissions.reports && module != TeamPermissions.settings;
      final actions = <String, bool>{};
      if (isFull) {
        actions['read'] = src['read'] == true;
        actions['create'] = src['create'] == true;
        actions['update'] = src['update'] == true;
        actions['delete'] = src['delete'] == true;
      } else {
        actions['read'] = src['read'] == true;
      }
      map[module] = actions;
    }
    return map;
  }

  String _extractRpcError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error is Map) {
        return (error['message'] ?? '').toString();
      }
    } catch (_) {}
    return body;
  }

  String _arabicRpc(String message) {
    if (message.contains('TOO_MANY_ATTEMPTS_TRY_LATER')) {
      return 'هذا البريد حاول كثيراً مؤخراً، حاول لاحقاً';
    }
    if (message.contains('EMAIL_EXISTS')) {
      return 'البريد مستخدم بالفعل';
    }
    if (message.contains('OPERATION_NOT_ALLOWED')) {
      return 'البريد/كلمة المرور غير مفعل في المشروع (فعّله في Firebase Auth)';
    }
    return message.replaceAll('_', ' ');
  }
}