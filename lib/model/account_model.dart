// lib/models/account_model.dart
// ملاحظة معمارية: هذا الملف أصبح واجهة تخويل (Facade) رفيعة لدعم التوافق
// العكسي مع المتصلين القائمين (account_controller / SplashScreen).
//
// التنفيذ الفعلي انتقل إلى features/account/data:
//   - AccountRemoteDataSource (FirebaseAuth + users/{uid})
//   - AccountLocalDataSource  (SharedPreferences: pending_accounts)
//   - AccountRepositoryImpl   (تنسيق مزامنة الحسابات المعلقة)
//   - AccountRepository       (العقد في domain)
//
// كل استدعاء هنا مجرد تمرير — لا يوجد أي منطق Firebase/SharedPreferences هنا.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/core/network/connectivity_service.dart';
import 'package:fkra/features/account/data/repositories/account_repository_impl.dart';
import 'package:fkra/features/account/domain/repositories/account_repository.dart';
import 'package:fkra/model/login_model.dart';

class AccountModel {
  final AccountRepository _repo = AccountRepositoryImpl();

  // التحقق من وجود اتصال بالإنترنت
  Future<bool> hasInternet() => ConnectivityService.hasInternet();

  // حفظ البيانات محلياً عند عدم وجود إنترنت
  Future<void> saveAccountLocally(Map<String, dynamic> userData) =>
      _repo.saveAccountLocally(userData);

  // مزامنة الحسابات المعلقة (تستدعى عند توفر الإنترنت)
  Future<int> syncPendingAccounts() => _repo.syncPendingAccounts();

  // إنشاء حساب جديد في Firebase
  Future<UserCredential> createAccountWithEmailPassword({
    required String email,
    required String password,
  }) =>
      _repo.createAccountWithEmailPassword(email: email, password: password);

  // حفظ بيانات المستخدم في Firestore
  Future<void> saveUserDataToFirestore({
    required String userId,
    required Map<String, dynamic> userData,
  }) =>
      _repo.saveUserDataToFirestore(userId: userId, userData: userData);

  // تحميل قائمة الحسابات المعلقة (للاستخدام في التحقق)
  Future<List<String>> getPendingAccounts() => _repo.getPendingAccounts();

  // ========== إرسال رسالة التحقق من البريد ==========
  Future<void> sendEmailVerification() => _repo.sendEmailVerification();

  // ========== تفكيك استثناءات Firebase Auth لعرض الرسالة الصحيحة ==========
  String? errorCodeOf(Object error) => _repo.errorCodeOf(error);

  String? errorMessageOf(Object error) => _repo.errorMessageOf(error);

  // ========== تسجيل الخروج ==========
  Future<void> signOut() async {
    await LoginModel.signOutPlatform();
    await LoginModel.clearSessionPrefs();
  }
}