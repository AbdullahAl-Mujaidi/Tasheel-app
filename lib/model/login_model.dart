// lib/model/login_model.dart
// ملاحظة معمارية: هذا الملف أصبح واجهة تخويل (Facade) رفيعة لدعم التوافق
// العكسي مع المتصلين القائمين (SplashScreen / LoginController / admin_portal /
// account_model / settings_model / member_settings_view).
//
// التنفيذ الفعلي انتقل إلى features/auth/data:
//   - AuthRemoteDataSource (Firebase Auth + Firestore + Google)
//   - AuthLocalDataSource  (SharedPreferences: الجلسة ومحاولات الدخول المعلّقة)
//   - AuthRepositoryImpl   (تنفيذ عقد AuthRepository)
//
// كل استدعاء هنا مجرد تمرير — لا يوجد أي منطق Firebase بعد الآن في هذا الملف.
import 'package:firebase_auth/firebase_auth.dart';

import '../features/auth/data/repositories/auth_repository_impl.dart';
import '../features/auth/domain/entities/auth_session.dart';
import '../features/auth/domain/repositories/auth_repository.dart';

class LoginModel {
  final AuthRepository _repo = AuthRepositoryImpl.instance;

  // ========== التحقق من الاتصال ==========
  Future<bool> hasInternet() => _repo.hasInternet();

  // ========== حفظ الجلسة محلياً ==========
  Future<void> saveSessionLocally(String userId, String email) =>
      _repo.saveSessionLocally(userId, email);

  // ========== حفظ محاولة تسجيل الدخول عند عدم الاتصال ==========
  Future<void> saveOfflineLoginAttempt(String email, String password) =>
      _repo.saveOfflineLoginAttempt(email, password);

  // ========== الحصول على محاولات تسجيل الدخول المعلقة ==========
  Future<List<Map<String, dynamic>>> getPendingLogins() =>
      _repo.getPendingLogins();

  // ========== مسح محاولات تسجيل الدخول المعلقة ==========
  Future<void> clearPendingLogins() => _repo.clearPendingLogins();

  // ========== حفظ قائمة محدثة من محاولات تسجيل الدخول المعلقة ==========
  Future<void> savePendingLogins(List<Map<String, dynamic>> logs) =>
      _repo.savePendingLogins(logs);

  // ========== تسجيل الدخول إلى Firebase ==========
  // يُعاد المستخدم الحالي من FirebaseAuth ليتوافق مع التوقيع القديم؛ منطق
  // المصادقة نفسه داخل AuthRemoteDataSource لا هنا.
  String? get lastAuthErrorCode => _repo.lastAuthErrorCode;

  Future<User?> loginWithEmailAndPassword(String email, String password) async {
    final AuthSession? session =
        await _repo.loginWithEmailAndPassword(email, password);
    if (session == null) return null;
    return FirebaseAuth.instance.currentUser;
  }

  // ========== تسجيل الدخول بواسطة Google ==========
  // يُعاد المستخدم الحالي من FirebaseAuth ليتوافق مع التوقيع القديم؛ بناء
  // Credential والمصادقة نفسها داخل AuthRemoteDataSource.
  Future<User?> signInWithGoogle({
    required String? accessToken,
    required String? idToken,
  }) async {
    final AuthSession? session = await _repo.signInWithGoogleCredential(
      accessToken: accessToken,
      idToken: idToken,
    );
    if (session == null) return null;
    return FirebaseAuth.instance.currentUser;
  }

  // ========== البريد الإلكتروني للمستخدم الحالي ==========
  String? get currentUserEmail => _repo.currentUserEmail;

  // ========== التحقق من حالة البريد الإلكتروني ==========
  Future<bool> isEmailVerified() => _repo.isEmailVerified();

  // ========== إعادة إرسال رسالة التحقق ==========
  Future<bool> resendEmailVerification() => _repo.resendEmailVerification();

  // ========== إرسال رسالة التحقق (تُستدعى لحظة منع الدخول) ==========
  Future<bool> sendVerificationEmail() => _repo.sendVerificationEmail();

  // ========== فحص ما إذا كان الحساب معلّقاً (تم حظره من لوحة المدير) ==========
  Future<bool> isAccountBlocked(String uid) => _repo.isAccountBlocked(uid);

  // ========== تعبئة بروفايل المستخدم من بيانات Google ==========
  Future<void> seedProfileFromGoogle({
    required String uid,
    String? displayName,
    String? email,
    String? photoURL,
  }) =>
      _repo.seedProfileFromGoogle(
        uid: uid,
        displayName: displayName,
        email: email,
        photoURL: photoURL,
      );

  // ========== إعادة تحميل بيانات المستخدم والتحقق من البريد ==========
  Future<bool> reloadUser() => _repo.reloadUser();

  // ========== مسح بيانات الجلسة المحفوظة محلياً ==========
  static Future<void> clearSessionPrefs() =>
      AuthRepositoryImpl.instance.clearSessionPrefs();

  // ========== تسجيل الخروج من المنصات (Firebase + Google) ==========
  static Future<void> signOutPlatform() =>
      AuthRepositoryImpl.instance.signOutPlatform();

  // ========== تسجيل الخروج ==========
  Future<void> signOut() => _repo.signOut();
}