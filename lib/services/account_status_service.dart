// ignore_for_file: avoid_print
// lib/services/account_status_service.dart
//
// مصدر الحقيقة الوحيد في جانب العميل لحالة الحساب (accountStatus).
//
// ⚠️ لماذا هذا الملف؟
// قبله كان فحص حالة الحساب موزّعاً في ثلاثة مواضع مختلفة (طبقة البيانات،
// المتحكم، شاشة البداية) بثلاث سلوكيات مختلفة، أهمها:
//   - حساب المفوّض (delegate) لم تُفحص حالته إطلاقاً عند الدخول بالبريد.
//   - أي خطأ شبكي كان يُترجم إلى "غير مقيَّد" (fail-open).
//   - لم تُفحص الحالة إطلاقاً أثناء الجلسة المفتوحة، فبقي المستخدم داخل
//     التطبيق بلا حدود بعد تقييده.
// الآن كل الفحوص تمرّ من هنا، والحالة تُقرأ من الخادم مباشرة (Source.server)
// فلا يصلحها كاش قديم ولا حذف لبيانات التطبيق.
//
// ملاحظة فصل مهم: هذا فحص *حساب* (accountStatus) لا فحص *عضوية*
// (membership.status). تقييد حساب لا يلغي عضويته في البيانات ولا يقيّد
// مالكَه، والعكس صحيح.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';

/// حالة الوصول للحساب كما يقرؤها الخادم.
enum AccountAccessState {
  /// لم يُقرأ بعد / تعذّرت القراءة (دون اتصال غالبًا) — لا تُحجب به الوظائف
  /// حمايةً لنظام العمل دون اتصال (Offline-First).
  unknown,

  /// الحساب نشط ومتاح.
  active,

  /// الحساب مقيد من إدارة التطبيق.
  suspended,
}

class AccountStatusService extends ChangeNotifier {
  AccountStatusService._();
  static final AccountStatusService instance = AccountStatusService._();

  /// القيم التي تعني "حساب مقيَّد" في حقل users/{uid}.status.
  /// نقبل 'blocked' و'suspended' معاً: مسار لوحة الإدارة الاحتياطي (بلا
  /// Cloud Functions) يكتب 'suspended' والخادم يكتب 'blocked'، ولا نريد ثغرة
  /// تنشأ من اختلاف التسمية بين المسارين.
  static const Set<String> _suspendedValues = {'suspended', 'blocked'};

  /// قراءة حالة الحساب من نص (مستخدم في المسارات وفي الاختبارات).
  static AccountAccessState parseStatus(Object? raw) {
    final status = raw?.toString().trim().toLowerCase() ?? '';
    if (status.isEmpty) return AccountAccessState.active;
    return _suspendedValues.contains(status)
        ? AccountAccessState.suspended
        : AccountAccessState.active;
  }

  /// قيمة BOOL المخزّنة في `users/{uid}.isActive`.
  ///
  /// الحقل مرآة لـ`status` يُكتب معه في نفس العملية. **FAIL-OPEN مقصود**:
  /// الوثائق القديمة (وكل الحسابات المنشأة قبل إضافة الحقل) لا تحوي
  /// `isActive` إطلاقاً، وافتراضها `false` كان سيقفل كل الحسابات القائمة.
  static bool parseIsActive(Object? raw) => raw != false;

  /// الحالة الفعلية = الحقلان معاً، و`false` في أيٍّ منهما يعني موقوفاً.
  ///
  /// نستخدم OR عمداً: تعارض الكتابة (كلاهما في عملية `set` واحدة) لا يعطي
  /// وصولاً لحسابٍ موثوق. قاعدةFail-closed هنا أهم منFail-open أعلاه.
  static AccountAccessState resolveState({Object? status, Object? isActive}) {
    if (!parseIsActive(isActive)) return AccountAccessState.suspended;
    return parseStatus(status);
  }

  AccountAccessState _state = AccountAccessState.unknown;
  AccountAccessState get state => _state;
  bool get isSuspended => _state == AccountAccessState.suspended;

  Timer? _timer;
  bool _watching = false;
  bool _checking = false;

  // ========== القراءة من الخادم (المصدر الموثوق) ==========

  /// يقرأ حالة الحساب من الخادم مباشرة بلا كاش.
  ///
  /// الفلسفة: عند الاتصال نقرأ من الخادم دائماً (لا نعتمد على
  /// Source.serverAndCache الذي قد يخدم قيمة 'active' قديمة). وعند الانقطاع
  /// نحتفظ بآخر حالة معروفة بدل افتراض "نشط" — فلا يُقلب حساب مقيد إلى
  /// "نشط" بسبب شبكة سيئة، ولا يُقفل مستخدمٌ نشط بسبب انقطاع مؤقت.
  Future<AccountAccessState> refresh({Duration timeout = const Duration(seconds: 8)}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _state = _set(AccountAccessState.unknown);

    if (_checking) return _state;
    _checking = true;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      // أول نجاح في التحقق = بداية المراقبة الدورية. بدونها لا يوجد أي
      // فحص أثناء الاستخدام، فيبقى الموقوف داخل التطبيق حتى رجوعه للواجهة.
      startWatching();
      return _set(resolveState(
          status: doc.data()?['status'], isActive: doc.data()?['isActive']));
    } catch (e) {
      // خطأ شبكة/صلاحية/انقطاع: لا نُسقط الحالة المعروفة ولا نفترض "نشط".
      print('تعذّر التحقق من حالة الحساب (يُحتفظ بآخر حالة): $e');
      return _state;
    } finally {
      _checking = false;
    }
  }

  /// فحص واحد سريع لحساب محدد (يُستخدم بعد المصادقة مباشرة).
  Future<AccountAccessState> checkUid(String uid,
      {Duration timeout = const Duration(seconds: 8)}) async {
    if (uid.isEmpty) return AccountAccessState.unknown;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      return resolveState(
          status: doc.data()?['status'], isActive: doc.data()?['isActive']);
    } catch (e) {
      print('تعذّر التحقق من حالة الحساب $uid: $e');
      return AccountAccessState.unknown;
    }
  }

  AccountAccessState _set(AccountAccessState next) {
    if (next == _state) return _state;
    _state = next;
    print('تغيّرت حالة الحساب إلى: $next');
    notifyListeners();
    return _state;
  }

  /// إعادة التعيين بعد تسجيل الخروج/الحذف.
  void reset() {
    _stopWatching();
    _set(AccountAccessState.unknown);
  }

  // ========== مراقب الجلسة القديمة ==========
  // يغطي "جلسة كانت مفتوحة قبل التقييد": يفحص دورياً وعند عودة التطبيق
  // للواجهة، ويُشعر الواجهة فور اكتشاف التقييد لإنهاء الجلسة.

  void startWatching({
    Duration interval = const Duration(minutes: 2),
  }) {
    if (_watching) return;
    _watching = true;
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  void _stopWatching() {
    _timer?.cancel();
    _timer = null;
    _watching = false;
  }

  /// يُستدعى عند عودة التطبيق إلى المقدمة.
  Future<void> checkOnResume() async {
    if (FirebaseAuth.instance.currentUser == null) {
      reset();
      return;
    }
    await refresh();
  }

  @override
  void dispose() {
    _stopWatching();
    super.dispose();
  }
}