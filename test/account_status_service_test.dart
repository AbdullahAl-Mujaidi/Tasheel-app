import 'package:flutter_test/flutter_test.dart';
import 'package:fkra/services/account_status_service.dart';

void main() {
  group('AccountStatusService.parseIsActive', () {
    test('false يعني موقوف', () {
      expect(AccountStatusService.parseIsActive(false), isFalse);
    });

    test('الحقل الغائب يُعامل كنشط (fail-open للوثائق القديمة)', () {
      expect(AccountStatusService.parseIsActive(null), isTrue);
      expect(AccountStatusService.parseIsActive(''), isTrue);
    });

    test('true يعني نشط', () {
      expect(AccountStatusService.parseIsActive(true), isTrue);
    });
  });

  group('AccountStatusService.parseStatus', () {
    test('suspended و blocked يعنيان موقوفاً', () {
      expect(
        AccountStatusService.parseStatus('suspended'),
        AccountAccessState.suspended,
      );
      expect(
        AccountStatusService.parseStatus('blocked'),
        AccountAccessState.suspended,
      );
      expect(
        AccountStatusService.parseStatus('BLOCKED'),
        AccountAccessState.suspended,
      );
    });

    test('active والفارغ يعنيان نشطاً', () {
      expect(AccountStatusService.parseStatus('active'), AccountAccessState.active);
      expect(AccountStatusService.parseStatus(null), AccountAccessState.active);
      expect(AccountStatusService.parseStatus(''), AccountAccessState.active);
    });
  });

  group('AccountStatusService.resolveState (الحقلان معاً)', () {
    test('isActive=false يمنع الدخول حتى لو كان status نشطاً', () {
      // الحالة الأهم: تعارض عكسي —Bool يقول موقوف والنص يقول نشط.
      expect(
        AccountStatusService.resolveState(status: 'active', isActive: false),
        AccountAccessState.suspended,
      );
    });

    test('status suspended يمنع الدخول حتى لو كان isActive=true', () {
      expect(
        AccountStatusService.resolveState(status: 'suspended', isActive: true),
        AccountAccessState.suspended,
      );
    });

    test('الحقلان معاً ⇒ موقوف (fail-closed)', () {
      expect(
        AccountStatusService.resolveState(status: 'blocked', isActive: false),
        AccountAccessState.suspended,
      );
    });

    test('الحقلان معاً ⇒ نشط', () {
      expect(
        AccountStatusService.resolveState(status: 'active', isActive: true),
        AccountAccessState.active,
      );
    });

    test('وثيقة قديمة بلا isActive تبقى نشطة حسب status', () {
      expect(
        AccountStatusService.resolveState(status: 'active', isActive: null),
        AccountAccessState.active,
      );
      expect(
        AccountStatusService.resolveState(status: 'suspended', isActive: null),
        AccountAccessState.suspended,
      );
    });
  });
}
