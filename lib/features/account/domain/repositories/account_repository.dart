// lib/features/account/domain/repositories/account_repository.dart
// عقد طبقة بيانات إنشاء الحساب (FirebaseAuth + users/{uid} + قائمة المعلّقة).
// ملاحظة: يرجع UserCredential لأن AccountController بحاجة له (uid / updateDisplayName)
// — تسوية معمارية متعمدة لتجنّب تعديل المتصلين الحاليين.
import 'package:firebase_auth/firebase_auth.dart';

abstract class AccountRepository {
  // ========== الحسابات المعلقة ==========
  Future<void> saveAccountLocally(Map<String, dynamic> userData);

  Future<List<String>> getPendingAccounts();

  Future<int> syncPendingAccounts();

  // ========== إنشاء الحساب ==========
  Future<UserCredential> createAccountWithEmailPassword({
    required String email,
    required String password,
  });

  Future<void> saveUserDataToFirestore({
    required String userId,
    required Map<String, dynamic> userData,
  });

  Future<void> sendEmailVerification();

  /// يستخرج كود خطأ Firebase Auth من استثناء (أو null إن لم يكن Auth).
  String? errorCodeOf(Object error);

  /// يستخرج رسالة خطأ Firebase Auth من استثناء (أو null إن لم يكن Auth).
  String? errorMessageOf(Object error);
}