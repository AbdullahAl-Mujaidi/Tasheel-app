// lib/features/auth/domain/repositories/auth_repository.dart
// عقد (Contract) طبقة المصادقة — تعريفي بحت لا يعرف شيئاً عن Firebase/Flutter.
//
// يطابق واجهة LoginModel القديمة تماماً حتى يبقى سلوك المتصلين (المتحكمات/
// الشاشات) كما هو، بينما ينتقل التنفيذ الفعلي إلى طبقة البيانات.
import '../entities/auth_session.dart';

abstract class AuthRepository {
  Future<bool> hasInternet();

  Future<void> saveSessionLocally(String userId, String email);

  Future<void> saveOfflineLoginAttempt(String email, String password);

  Future<List<Map<String, dynamic>>> getPendingLogins();

  Future<void> clearPendingLogins();

  Future<void> savePendingLogins(List<Map<String, dynamic>> logs);

  /// آخر كود خطأ من Firebase Auth (مثل user-disabled) لعرض الرسالة الصحيحة.
  String? get lastAuthErrorCode;

  /// تسجيل الدخول بالبريد وكلمة المرور. يعيد null عند الفشل.
  Future<AuthSession?> loginWithEmailAndPassword(
      String email, String password);

  /// تسجيل الدخول بواسطة Google (Credential جاهز من رموز GoogleSignIn).
  /// يعيد null عند غياب المستخدم، ويُعيد الرمي على خطأ Firebase Auth كي
  /// يُعالجه المتحكم عبر lastAuthErrorCode.
  Future<AuthSession?> signInWithGoogleCredential({
    required String? accessToken,
    required String? idToken,
  });

  /// البريد الإلكتروني للمستخدم الحالي (منحىً ومعرّى) أو null.
  String? get currentUserEmail;

  Future<bool> isEmailVerified();

  Future<bool> resendEmailVerification();

  Future<bool> sendVerificationEmail();

  Future<bool> isAccountBlocked(String uid);

  Future<void> seedProfileFromGoogle({
    required String uid,
    String? displayName,
    String? email,
    String? photoURL,
  });

  Future<bool> reloadUser();

  Future<void> clearSessionPrefs();

  Future<void> signOutPlatform();

  Future<void> signOut();
}