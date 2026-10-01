// ignore_for_file: avoid_print
// lib/services/account_deletion_service.dart
//
// ينفّذ "حذف حسابي": الحذف على الخادم أولاً، ثم إتلاف كل الأثر على هذا الجهاز.
//
// ⚠️ مبدأ الحسم: الهدف على الخادم هو `context.auth.uid` في دالة
// `deleteOwnAccount` — لا يوجد أي uid يرسله العميل، فلا يمكن نسخ العملية على
// جهاز آخر ولا استغلالها على حساب غيرك. Cloud Function تشترط دخولاً حديثاً
// (re-auth) لأن الحذف غير قابل للاسترجاع.
//
// ترتيب التنفيذ مقصود:
//   1) تأكيد الهوية (re-auth) — لأن الخادم سيرفض أي توكن قديم.
//   2) الحذف على الخادم.
//   3) تنظيف الجهاز (محلياً) — يعمل حتى لو فشل (2)، فبقاء بيانات حساب محذوف
//      على جهازه تسريب. ونُبلغ المستخدم إن فشل الخادم.
//   4) تسجيل الخروج وتوجيه المستخدم لشاشة الدخول.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../db/database_helper.dart';
import '../features/auth/data/datasources/auth_remote_datasource.dart';
import '../view/login_view.dart';
import 'account_status_service.dart';
import 'member_session_service.dart';

/// نتيجة محاولة الحذف — لعرض رسالة دقيقة للمستخدم (لا "فشل" كلي).
class AccountDeletionResult {
  const AccountDeletionResult({
    required this.serverSucceeded,
    required this.localPurged,
    required this.removedMemberships,
    this.authAccountLeftBehind = false,
    this.firestoreOnlyFallback = false,
    this.errorMessage,
    this.errorCode,
  });

  /// هل حُذف الحساب على الخادم فعلياً؟
  final bool serverSucceeded;

  /// هل نُظّف كل الأثر المحلي؟ (يبقى صحيحاً حتى عند فشل الخادم)
  final bool localPurged;

  /// عدد علاقات التفويض التي أُزيلت عن مالكين آخرين.
  final int removedMemberships;

  /// حُذفت بيانات الخادم لكن تعذّر حذف حساب المصادقة (حساب "زومبي").
  final bool authAccountLeftBehind;

  /// حُذفت البيانات عبر المسار البديل من العميل (دالة Cloud غير منشورة).
  /// في هذه الحالة بيانات Firestore محذوفة لكن حساب Auth لم يُحذف.
  final bool firestoreOnlyFallback;

  final String? errorMessage;
  final String? errorCode;

  bool get fullySucceeded =>
      serverSucceeded && localPurged && !authAccountLeftBehind;
}

class AccountDeletionService extends ChangeNotifier {
  AccountDeletionService._();
  static final AccountDeletionService instance = AccountDeletionService._();

  bool _busy = false;
  bool get isBusy => _busy;
  String? _error;
  String? get error => _error;

  // ========== 1) تأكيد الهوية ==========
  // الخادم (SELF_DELETE_MAX_AUTH_AGE_MS) لا يقبل إلا توكناً صادراً من دخول
  // خلال آخر 30 دقيقة، لأن الحذف غير قابل للاسترجاع.
  //
  // uid وحده لا يكفي: uid ثابت في رموز الوصول الموقّعة (وربم في نسخة قديمة من
  // التطبيق على جهاز آخر)، فإعادة التأكيد هي ما يحوّل "يملك uid" إلى
  // "يجلس داخل هذه الجلسة الآن".

  /// هل هذا الحساب مرتبط بمزوّد كلمة مرور (يحتاج المستخدم لإدخالها)؟
  ///
  /// يعتمد على `providerData` لا على شكل البريد: حساب Google قد يكون بأي
  /// نطاق، والحساب بالبريد قد يكون على gmail.
  bool requiresPassword([User? user]) {
    final u = user ?? FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    return u.providerData.any((p) => p.providerId == 'password');
  }

  /// إعادة تأكيد الهوية بكلمة المرور لتحديث auth_time (قابل للتراجع: يمكن
  /// للمستخدم الضغط "إلغاء" قبل التنفيذ).
  Future<void> reauthenticateWithPassword(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw AccountDeletionException('لا توجد جلسة مفتوحة');
    }
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw AccountDeletionException('لا يمكن إعادة تأكيد الحساب بلا بريد');
    }
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// إعادة تأكيد الهوية لحساب Google (لا كلمة مرور له): دخول جديد عبر Google
  /// يُحدّث auth_time. لا نطلب كلمة مرور لحساب Google ولا نتظاهر بأنه مرتبط
  /// بمزوّد 'password'.
  Future<void> reauthenticateWithGoogle() async {
    final google = GoogleSignIn();
    // مسح الجلسة القديمة لضمان اختيار الحساب ولتجنب خطأ `invoke error.4`
    try {
      await google.signOut();
    } catch (_) {}

    final account = await google.signIn();
    if (account == null) {
      throw AccountDeletionException('أُلغيت إعادة التأكيد');
    }
    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  // ========== 2 + 3 + 4) الحذف ثم التنظيف ثم الخروج ==========
  Future<AccountDeletionResult> deleteMyAccount() async {
    if (_busy) {
      return const AccountDeletionResult(
        serverSucceeded: false,
        localPurged: false,
        removedMemberships: 0,
        errorMessage: 'الحذف جارٍ بالفعل',
      );
    }
    _busy = true;
    _error = null;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _busy = false;
      notifyListeners();
      return const AccountDeletionResult(
        serverSucceeded: false,
        localPurged: false,
        removedMemberships: 0,
        errorMessage: 'لا توجد جلسة مفتوحة',
      );
    }

    // المعرّفات التي تحمل بيانات هذا المستخدم محلياً: uid الخاص به، وuid المالك
    // إن كان مفوّضاً (بياناته تُخزَّن تحت المالك محلياً).
    final uid = user.uid;

    final purgeIds = <String>{uid};
    final session = MemberSessionService.instance;
    final ownerUid = session.ownerUid;
    if (ownerUid.isNotEmpty && ownerUid != uid) purgeIds.add(ownerUid);

    var serverSucceeded = false;
    var authAccountLeftBehind = false;
    var firestoreOnlyFallback = false;
    var removedMemberships = 0;
    String? errMsg;
    String? errCode;

    try {
      final result = await _callDeleteOwnAccount();
      serverSucceeded = true;
      authAccountLeftBehind = result['authDeleted'] == false;
      removedMemberships = (result['removedMemberships'] as num?)?.toInt() ?? 0;
      print('تم حذف الحساب على الخادم. علاقات أُزيلت: $removedMemberships');
    } on FirebaseFunctionsException catch (e) {
      errCode = e.code;
      errMsg = switch (e.code) {
        'failed-precondition' =>
          'انتهت مدة التأكيد. أعد تسجيل الدخول ثم حاول مجدداً.',
        'permission-denied' =>
          'لا يمكن حذف هذا الحساب (حساب محمي أو مدير عام).',
        'unauthenticated' => 'انتهت الجلسة. أعد تسجيل الدخول ثم حاول مجدداً.',
        // الدالة غير منشورة/غير منشورة بعد على المشروع ⇒ الحذف لم يحدث إطلاقاً.
        'not-found' =>
          'خدمة حذف الحساب غير متاحة حالياً. تواصل مع الإدارة لتفعيلها ثم أعد المحاولة.',
        'unavailable' || 'deadline-exceeded' =>
          'تعذّر الوصول للخدمة. تحقّق من الإنترنت ثم أعد المحاولة.',
        _ => 'تعذّر حذف الحساب من الخادم. حاول مجدداً أو تواصل مع الإدارة.',
      };
      print('فشل حذف الحساب (${e.code}): ${e.message}');

      // المسار البديل: الدالة غير منشورة أو الخدمة غير متاحة ⇒ لم يُحذف
      // شيء على الخادم. نحاول حذف Firestore مباشرة قبل الاستسلام.
      if (_isCallableUnavailable(e.code)) {
        print('محاولة المسار البديل (حذف Firestore من العميل)…');
        try {
          final removed = await _clientSideFirestoreDeletion(uid);
          
          bool authDeleted = false;
          try {
            await FirebaseAuth.instance.currentUser?.delete();
            authDeleted = true;
            print('تم حذف حساب Auth بنجاح من العميل.');
          } catch (authError) {
            print('تعذّر حذف حساب Auth: $authError');
          }

          serverSucceeded = true;
          authAccountLeftBehind = !authDeleted;
          firestoreOnlyFallback = true;
          removedMemberships = removed;
          errCode = e.code;
          errMsg = null;
          print('اكتمل المسار البديل. علاقات أُزيلت: $removed — حالة بقاء حساب Auth: $authAccountLeftBehind.');
        } catch (fe) {
          print('فشل المسار البديل أيضاً: $fe');
          errMsg = 'تعذّر حذف بيانات الحساب. تواصل مع الإدارة.';
          errCode = 'client-fallback-failed';
        }
      }
    } catch (e) {
      errMsg = 'تعذّر الاتصال بالخادم. تأكّد من الإنترنت ثم حاول مجدداً.';
      print('فشل حذف الحساب: $e');
    }

    // ⚠️ قاعدة صارمة: لا نمسح بيانات الجهاز إلا إذا أكّد الخادم أن الحذف
    // تم. المسح عند فشل الطلب = فقدان بيانات لم تُحذف من الخادم، ويترك
    // المستخدم بحساب حيّ بلا بيانات محلية. النسخة القديمة كانت تمسح دائماً.
    var localPurged = serverSucceeded;
    if (serverSucceeded) {
      try {
        await _purgeLocalData(uid, purgeIds);
      } catch (e) {
        localPurged = false;
        errMsg ??= 'حُذف حسابك لكن تعذّر تنظيف بيانات هذا الجهاز. أعد تثبيت التطبيق.';
        print('فشل التنظيف المحلي: $e');
      }
    }

    if (serverSucceeded) {
      // الخروج مطلوب دائماً بعد نجاح الحذف.
      try {
        await AuthRemoteDataSource.instance.signOutPlatform();
      } catch (_) {}
    }

    _busy = false;
    notifyListeners();

    return AccountDeletionResult(
      serverSucceeded: serverSucceeded,
      localPurged: localPurged,
      removedMemberships: removedMemberships,
      authAccountLeftBehind: authAccountLeftBehind,
      firestoreOnlyFallback: firestoreOnlyFallback,
      errorMessage: errMsg,
      errorCode: errCode,
    );
  }

  /// هل الدالة غير موجودة/غير متاحة ⇒ الحذف لم يحدث على الخادم إطلاقاً؟
  ///
  /// - `not-found`: الدالة غير منشورة على المشروع (الوضع الحالي).
  /// - `unavailable`: انقطاع مؤقت في Cloud Functions.
  /// - `deadline-exceeded`: انتهاء المهلة قبل التنفيذ.
  bool _isCallableUnavailable(String? code) =>
      code == 'not-found' ||
      code == 'unavailable' ||
      code == 'deadline-exceeded';

  Future<Map<String, dynamic>> _callDeleteOwnAccount() async {
    final callable = FirebaseFunctions.instance.httpsCallable('deleteOwnAccount');
    final res = await callable.call();
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  // ========== 2.5) مسار بديل: حذف Firestore من العميل ==========
  ///
  /// يعمل إذا كانت دالة Cloud غير منشورة أو غير متاحة (مثلاً الخطة المجانية).
  ///
  /// يقوم هذا المسار بحذف كامل بيانات المستخدم من Firestore عبر التطبيق نفسه.
  /// كما يحاول التطبيق بعد هذه الدالة حذف حساب المصادقة (Auth) باستخدام
  /// `user.delete()` والذي يتطلب تسجيلاً حديثاً (وهو ما تم طلبه من المستخدم).
  ///
  /// ⚠️ يعتمد على القواعد:
  ///   - `users/{uid}` يحذفه المالك النشط فقط (لا الموقوف/المحظور).
  ///   - `users/{ownerUid}/team_members/{uid}` يحذفها صاحب العضوية نفسها.
  ///   - `member_lookups/{uid}` يكتبه صاحبها.
  /// يعيد عدد علاقات التفويض التي أُزيلت، ويرمي استثناءً عند الفشل الجذري.
  Future<int> _clientSideFirestoreDeletion(String uid) async {
    final db = FirebaseFirestore.instance;

    // أ) عضوياتي عند كل مالك — collectionGroup لا يحتاج معرفة الـ ownerUid.
    var removedMemberships = 0;
    try {
      final snap = await db
          .collectionGroup('team_members')
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in snap.docs) {
        try {
          await doc.reference.delete();
          removedMemberships++;
        } catch (e) {
          print('تعذّر حذف العضوية ${doc.reference.path}: $e');
        }
      }
    } catch (e) {
      print('تعذّر جلب العضويات للحذف: $e');
    }

    // ب) فهرس العضوية الخاص بي.
    try {
      await db.collection(FirestoreCollections.memberLookups).doc(uid).delete();
    } catch (e) {
      print('تعذّر حذف member_lookups/$uid: $e');
    }

    // ج) كل بيانات ملفّي: شجرة `users/{uid}` بالكامل ثم الوثيقة نفسها.
    //    الحذف بالترتيب (الأبناء أولاً) لأن حذف الأب لا يحذف أبناءه.
    final userRef = db.collection(FirestoreCollections.users).doc(uid);
    try {
      for (final name in _userSubcollections) {
        await _deleteCollectionTree(userRef.collection(name));
      }
    } catch (e) {
      print('تعذّر حذف شجرة users/$uid: $e');
      rethrow;
    }
    await userRef.delete();
    return removedMemberships;
  }

  /// المجموعات الفرعية المعروفة داخل `users/{uid}`.
  ///
  /// Firestore لا يتيح للعميد تعداد المجموعات الفرعية لوثيقة، فتُدرج الأسماء
  /// صراحةً. القائمة مطابقة لـ`deleteDocTree` في `functions/index.js`.
  static const List<String> _userSubcollections = [
    FirestoreCollections.businesses,
    FirestoreCollections.workers,
    FirestoreCollections.expenses,
    FirestoreCollections.transactions,
    FirestoreCollections.customFields,
    FirestoreCollections.devices,
    FirestoreCollections.teamMembers,
  ];

  /// يحذف مجموعة كاملة بشكل متكرر (تنزل للمستويات الأعمق ثم للأبناء).
  Future<void> _deleteCollectionTree(Query<Map<String, dynamic>> col) async {
    for (final doc in (await col.get()).docs) {
      for (final name in _userSubcollections) {
        await _deleteCollectionTree(doc.reference.collection(name));
      }
      await doc.reference.delete();
    }
  }

  // ========== 3) إتلاف الأثر المحلي ==========
  Future<void> _purgeLocalData(String uid, Set<String> purgeIds) async {
    // أ) قاعدة البيانات المحلية — كل الجداول.
    await DatabaseHelper.instance.purgeUserData(purgeIds.toList());

    // ب) SharedPreferences — الجلسة، محاولات الدخول المعلّقة (تحتوي كلمات
    //    مرور بنص صريح)، عضوية المفوّض، وأي مفاتيح cached أخرى.
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      PrefKeys.userId,
      PrefKeys.isLoggedIn,
      PrefKeys.userEmail,
      PrefKeys.loginTime,
      PrefKeys.loggedInUser,
      PrefKeys.pendingLogins,
      PrefKeys.pendingAccounts,
      PrefKeys.sessionOwnerUid,
      PrefKeys.sessionMemberUid,
    ]) {
      await prefs.remove(key);
    }

    // ج) كاش Firestore على الجهاز (بيانات قد تكون خارج SQLite بعد إزاحة
    //    المصدر إلى Firestore).
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .delete();
      // delete على doc غير موجود ينجح، ولا يمسّ بيانات غيره.
    } catch (e) {
      print('تعذّر مسح كاش Firestore للحساب: $e');
    }

    // د) إعادة تعيين الخدمات التي تحتفظ بحالة في الذاكرة.
    await MemberSessionService.instance.clearSession();
    AccountStatusService.instance.reset();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ========== إعادة التوجيه بعد الحذف ==========

  /// ينتقل إلى شاشة الدخول بشكل آمن بعد استقرار شجرة العناصر.
  ///
  /// ⚠️ لماذا لا ننتقل مباشرةً بـ`pushAndRemoveUntil`؟
  /// لأن `pushAndRemoveUntil` يدمّر المكدس كاملاً (ومنه `Homepage`)، وحالة
  /// الحذف تُطلق ثلاث عمليات على نفس الإطار:
  ///   1) `clearSession()` → يُخطر `Homepage` → `setState` → إعادة بناء قائمة
  ///      التبويبات وتبديل `body` من صفحة إلى أخرى.
  ///   2) خروج حوار إعادة التأكيد من الـ Overlay (ما زال في حركته).
  ///   3) تدمير المسار بالكامل.
  /// اجتماعها في إطار واحد يجعل Flutter يُفعّل عنصراً موروثاً (InheritedElement)
  /// بينما ما زال له تابعون مسجّلون ⇒ انهيار
  /// `'package:flutter/src/widgets/framework.dart': '_dependents.isEmpty': is not true`.
  ///
  /// الحل: نضمن جدولة إطار، ننتظر اكتماله (فتنفّذ 1 و2)، ثم ننتقل.
  static Future<void> redirectToLogin(
    BuildContext context, {
    String? message,
    Color? backgroundColor,
  }) async {
    if (!context.mounted) return;

    // نلتقط الـ navigator قبل أي await: استعمال context بعد تفكيكه خطأ.
    final navigator = Navigator.of(context);

    // `scheduleFrame` يضمن وجود إطار قاد، فلا ينتظر `endOfFrame` إلى الأبد.
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (ctx) {
          if (message != null) {
            // الرسالة تُعرض على messenger المسار الجديد. عرضها على messenger
            // القديم محكوم عليه بالاختفاء مع المسار في نفس اللحظة، فلا يراها
            // المستخدم إطلاقاً.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(message),
                backgroundColor: backgroundColor,
              ));
            });
          }
          return const LoginScreen();
        },
      ),
      (route) => false,
    );
  }
}

class AccountDeletionException implements Exception {
  AccountDeletionException(this.message);
  final String message;
  @override
  String toString() => message;
}
