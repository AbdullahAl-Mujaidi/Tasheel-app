// lib/core/errors/failures.dart
// تسلسل Failures موحّد لنظام معالجة الأخطاء في التطبيق.
//
// الغرض: إعطاء كل طبقة نوعاً واضحاً للخطأ بدل `print` العشوائي وأكواد
// الـ String المجهولة المنتشرة حالياً. تتبنى الطبقات الجديدة (Repositories/
// UseCases) هذا التسلسل، وتُحافظ الطبقات الحالية على سلوكها حتى تُرحَّل.
abstract class Failure {
  final String message;
  const Failure([this.message = 'حدث خطأ غير متوقع']);
}

/// خطأ في منطق الخادم أو الاستجابة غير المتوقعة (Firestore/Cloud Functions).
class ServerFailure extends Failure {
  const ServerFailure([super.message]);
}

/// لا يوجد اتصال بالإنترنت أو فشل طلب شبكي.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'لا يوجد اتصال بالإنترنت']);
}

/// فشل القراءة/الكتابة في التخزين المحلي (SQLite / SharedPreferences / ملفات).
class CacheFailure extends Failure {
  const CacheFailure([super.message = 'فشل الوصول إلى التخزين المحلي']);
}

/// مشاكل المصادقة أو الجلسة.
class AuthenticationFailure extends Failure {
  const AuthenticationFailure([super.message = 'خطأ في تسجيل الدخول']);
}

/// رفض صلاحية الأمان في Firestore أو صلاحية مستخدم.
class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'لا تملك صلاحية تنفيذ هذه العملية']);
}

/// بيانات الإدخال غير صالحة.
class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'البيانات المدخلة غير صحيحة']);
}

// ================ Result Pattern خفيف ================
// يفصل نتيجة العملية إلى نجاح/فشل صريحين. يُستخدم في UseCases/Repositories
// الجديدة حيث يوجد معنى حقيقي، دون إجبار الطبقات القديمة على استبدال
// سلوكها الحالي.

sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

final class FailureResult<T> extends Result<T> {
  final Failure error;
  const FailureResult(this.error);
}