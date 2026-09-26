// lib/core/network/connectivity_service.dart
// نقطة واحدة موحدة للتحقق من الاتصال بالإنترنت.
//
// كانت النسخة السابقة تحتوي على 9 تعريفات متطابقة من
// `InternetAddress.lookup('google.com')` داخل كل نموذج وخدمة الجلسة، مما يجعل
// أي تعديل مستقبلي في منطق التحقق يحتاج تعديل كل المواقع. هذا الكلاس يجمعها
// جميعاً بنفس السلوك السابق تماماً (لا تغيير في أي timeout أو نتيجة).
import 'dart:async';
import 'dart:io';

class ConnectivityService {
  ConnectivityService._();

  /// المهلة القياسية المستخدمة في النماذج سابقاً (5 ثوانٍ).
  static const Duration standardTimeout = Duration(seconds: 5);

  /// المهلة السريعة المستخدمة في خدمة الجلسة سابقاً (4 ثوانٍ).
  static const Duration quickTimeout = Duration(seconds: 4);

  /// نفس سلوك hasInternet() القديمة في النماذج حرفياً.
  static Future<bool> hasInternet(
      {Duration timeout = standardTimeout}) async {
    try {
      final result =
          await InternetAddress.lookup('google.com').timeout(timeout);
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// نفس سلوك فحص الاتصال داخل عضو _startPeriodicRefresh في خدمة الجلسة.
  static Future<bool> hasQuickInternet() =>
      hasInternet(timeout: quickTimeout);
}