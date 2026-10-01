import 'package:flutter_test/flutter_test.dart';
import 'package:fkra/services/account_access_guard.dart';

void main() {
  group('EffectiveAccess.isBlocked', () {
    test('حسابي أنا موقوف ⇒ يُنهى الجلسة', () {
      expect(EffectiveAccess.suspendedBySelf.isBlocked, isTrue);
    });

    test('تعذّر التحقق ⇒ يُمنع الدخول (fail-closed)', () {
      expect(EffectiveAccess.unknown.isBlocked, isTrue);
    });

    // ⭐ هذا هو الإصلاح: إيقاف المالك لا يجوز أن يوقف حساب التابع النشط.
    // كان suspendedByOwner.isBlocked == true ⇒ يخرج قاسم من حسابه الشخصي
    // فلا يستطيع الدخول لمجرد أن محمد (مالكه) أوقفه المدير.
    test('إيقاف المالك لا يوقف حسابي ⇒ الجلسة تبقى', () {
      expect(EffectiveAccess.suspendedByOwner.isBlocked, isFalse);
    });

    test('النشط غير محظور', () {
      expect(EffectiveAccess.active.isBlocked, isFalse);
    });
  });

  group('EffectiveAccess.requiresPersonalScope', () {
    test('إيقاف المالك ⇒ يُلغى التفويض فقط', () {
      expect(EffectiveAccess.suspendedByOwner.requiresPersonalScope, isTrue);
    });

    test('حسابي أنا موقوف ⇒ لا تفويض بل خروج', () {
      expect(EffectiveAccess.suspendedBySelf.requiresPersonalScope, isFalse);
    });

    test('النشط لا يحتاج إسقاط تفويض', () {
      expect(EffectiveAccess.active.requiresPersonalScope, isFalse);
      expect(EffectiveAccess.unknown.requiresPersonalScope, isFalse);
    });
  });

  group('EffectiveAccess.notice', () {
    test('رسالة إيقاف المالك توضّح أن الدخول شخصي وليس رفضاً', () {
      final notice = EffectiveAccess.suspendedByOwner.notice;
      expect(notice, isNotEmpty);
      expect(notice, contains('الشخصي'));
    });

    test('كل الحالات غير النشطة لها رسالة', () {
      expect(EffectiveAccess.suspendedBySelf.notice, isNotEmpty);
      expect(EffectiveAccess.unknown.notice, isNotEmpty);
      expect(EffectiveAccess.active.notice, isEmpty);
    });
  });
}
