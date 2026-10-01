// lib/services/account_access_guard.dart
//
// مصدر واحد لـ"الوصول الفعلي" لأي مستخدم.
//
// المشكلة التي يحلها: كل مسارات الدخول كانت تفحص `users/{uid}` الخاص
// بالمستخدم المسجِّل دخوله فقط. المستخدم التابع (delegate) — مثل علي وقاسم
// عند تفويض محمد —_uid_ الخاص به يبقى نشطاً، فيُسمح له بفتح التطبيق ورؤية
//! أعمال مالكه الموقوف والتحكم فيها، لأن "حالة الحساب" كانت تعني دائماً
// "حسابي أنا" لا "حسابي + حسابي الذي أفوّضه".
//
// الحل: الوصول الفعلي = حالتَي (أنا) + (المالك الذي أعرض حسابه) إن وُجد.
//
// ⚠️ التمييز الحاسم: الحسابان ليسا على قدم المساواة.
//   - suspendedBySelf  ⇒ حسابي أنا موقوف ⇒ يُنهى جلستي.
//   - suspendedByOwner ⇒ حسابي أنا **نشط**، والمالك وحده موقوف ⇒ يُلغى
//     التفويض فقط وأدخل حسابي الشخصي. لمّا كان هذا يخرج المستخدم من حسابه
//     الشخصي أيضاً، لم يستطع قاسم (نشط) الدخول لمجرد إيقاف محمد.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'account_status_service.dart';
import 'member_session_service.dart';

/// نتيجة تقييم الوصول الفعلي.
enum EffectiveAccess {
  /// المستخدم نفسه نشط ومالكه (إن وُجد) نشط.
  active,

  /// حساب المستخدم نفسه موقوف/محظور.
  suspendedBySelf,

  /// حساب المستخدم **نشط**، لكن المالك الذي فوّضه موقوف.
  ///
  /// ⭐ هذا لا يمنع الدخول. حساب قاسم/علي مستقل ونشط، ولا حقّ للإدارة في
  /// إيقافه لمجرد أن مالكه موقوف. المطلوب: يُسقط نطاق التفويض فقط
  /// (`switchToPersonal`) ويدخل حسابه الشخصي. كان هذا يخرج المستخدم من
  /// حسابه الشخصي أيضاً — وهو ما منع قاسم من الدخول أصلاً.
  suspendedByOwner,

  /// تعذّر التحقق (شبكة/صلاحية) — لا يُعامل كنشط.
  unknown;

  /// حالة تمنع الجلسة نهائياً (تُخرج المستخدم من التطبيق).
  ///
  /// لا يشمل [suspendedByOwner]: إيقاف المالك يُسقط تفويضه فقط.
  bool get isBlocked =>
      this == EffectiveAccess.suspendedBySelf ||
      this == EffectiveAccess.unknown;

  /// يجب التخلي عن نطاق المالك والدخول بالحساب الشخصي (مع بقاء المستخدم).
  bool get requiresPersonalScope =>
      this == EffectiveAccess.suspendedByOwner;

  /// رسالة تُعرض للمستخدم في شاشة الدخول.
  String get notice => switch (this) {
        EffectiveAccess.suspendedBySelf => 'حسابك موقوف. تواصل مع الإدارة.',
        EffectiveAccess.suspendedByOwner =>
          'تم إيقاف حساب المالك الذي فوّضك، لذلك تم إلغاء التفويض. تدخل الآن إلى حسابك الشخصي.',
        EffectiveAccess.unknown =>
          'تعذّر التحقق من حالة حسابك. اتصل بالإنترنت وأعد فتح التطبيق.',
        EffectiveAccess.active => '',
      };
}

class AccountAccessGuard extends ChangeNotifier {
  AccountAccessGuard._();

  static final AccountAccessGuard instance = AccountAccessGuard._();

  /// آخر حالة مُقيمة — يستمع إليها `main.dart` لإنهاء الجلسة فور اكتشافها.
  EffectiveAccess? get access => _access;
  EffectiveAccess? _access;

  Timer? _ownerTimer;

  /// تقييم الوصول الفعلي.
  ///
  /// [includeSelf] = false يُستخدم في المراقبة الدورية: حالة الحساب نفسه
  /// يغطّيها بالفعل مؤقّت [AccountStatusService]، فالفحص حينها يقرأ وثيقة
  /// المالك فقط — قراءة واحدة لكل تابع بدل قراءتين.
  Future<EffectiveAccess> evaluate({
    bool includeSelf = true,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) return _set(EffectiveAccess.unknown) ?? EffectiveAccess.unknown;

    if (includeSelf) {
      final self = await AccountStatusService.instance.refresh(timeout: timeout);
      // ملاحظة: `refresh` عند فشل الشبكة يُبقي آخر حالة معروفة ولا يفترض
      // "نشط"، فإن كان `_state` مجهولاً (إقلاع جديد بلا اتصال) نمنع الدخول.
      if (self == AccountAccessState.suspended) {
        return _set(EffectiveAccess.suspendedBySelf) ?? EffectiveAccess.suspendedBySelf;
      }
      if (self == AccountAccessState.unknown) {
        return _set(EffectiveAccess.unknown) ?? EffectiveAccess.unknown;
      }
    }

    // لا تفويض معروض ⇒ الحساب الشخصي وحده يحسم.
    final session = MemberSessionService.instance;
    final ownerUid = session.ownerUid.trim();
    if (!session.isSubUser || ownerUid.isEmpty || ownerUid == auth.uid) {
      return _set(EffectiveAccess.active) ?? EffectiveAccess.active;
    }

    // ⚠️ البوابة الناقصة سابقاً: لا بد من فحص المالك نفسه، لا الاكتفاء بأن
    // وثيقة العضوية ما زالت `status: active` — فسند المالك لا يغيّرها.
    final owner =
        await AccountStatusService.instance.checkUid(ownerUid, timeout: timeout);
    if (owner == AccountAccessState.suspended) {
      return _set(EffectiveAccess.suspendedByOwner) ?? EffectiveAccess.suspendedByOwner;
    }
    if (owner == AccountAccessState.unknown) {
      return _set(EffectiveAccess.unknown) ?? EffectiveAccess.unknown;
    }
    return _set(EffectiveAccess.active) ?? EffectiveAccess.active;
  }

  /// مراقبة دورية لحالة المالك أثناء الاستخدام.
  ///
  /// تغطي "متابعة أوقفت حسابها والتطبيق مفتوح": الحارس يكتشف الإيقاف خلال
  /// [interval] ويُشعر `main.dart` فيُخرج المستخدم فعلياً — بدل بقائه داخل
  /// مساحة المالك الموقوف. التكلفة صفر لأصحاب الحسابات (لا عضوية ⇒ لا قراءة).
  void startOwnerWatch({Duration interval = const Duration(minutes: 2)}) {
    if (_ownerTimer != null) return;
    _ownerTimer = Timer.periodic(interval, (_) async {
      if (FirebaseAuth.instance.currentUser == null) return;
      if (!MemberSessionService.instance.isSubUser) return;
      await evaluate(includeSelf: false);
    });
  }

  void stopOwnerWatch() {
    _ownerTimer?.cancel();
    _ownerTimer = null;
  }

  /// تصفير بعد الخروج/الحذف حتى لا تتسرّب حالة إلى جلسة لاحقة.
  void reset() {
    stopOwnerWatch();
    _set(null);
  }

  EffectiveAccess? _set(EffectiveAccess? next) {
    if (next == _access) return _access;
    _access = next;
    notifyListeners();
    return _access;
  }

  @override
  void dispose() {
    stopOwnerWatch();
    super.dispose();
  }
}
