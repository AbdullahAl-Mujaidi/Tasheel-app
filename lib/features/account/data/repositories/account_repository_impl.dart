// lib/features/account/data/repositories/account_repository_impl.dart
// تنفيذ عقد AccountRepository: تنسيق مزامنة الحسابات المعلقة ورفعها إلى
// Firebase. منطق الحلقة منقول حرفياً من AccountModel.syncPendingAccounts.
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/repositories/account_repository.dart';
import '../datasources/account_local_datasource.dart';
import '../datasources/account_remote_datasource.dart';

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl();

  final AccountLocalDataSource _local = AccountLocalDataSource.instance;
  final AccountRemoteDataSource _remote = AccountRemoteDataSource.instance;

  @override
  Future<void> saveAccountLocally(Map<String, dynamic> userData) =>
      _local.saveAccountLocally(userData);

  @override
  Future<List<String>> getPendingAccounts() => _local.getPendingAccounts();

  @override
  Future<UserCredential> createAccountWithEmailPassword({
    required String email,
    required String password,
  }) =>
      _remote.createUserWithEmailPassword(email: email, password: password);

  @override
  Future<void> sendEmailVerification() => _remote.sendEmailVerification();

  @override
  String? errorCodeOf(Object error) =>
      error is FirebaseAuthException ? error.code : null;

  @override
  String? errorMessageOf(Object error) =>
      error is FirebaseAuthException ? error.message : null;

  @override
  Future<void> saveUserDataToFirestore({
    required String userId,
    required Map<String, dynamic> userData,
  }) =>
      _remote.saveUserDataToFirestore(userId: userId, userData: userData);

  @override
  Future<int> syncPendingAccounts() async {
    final pendingAccounts = await _local.getPendingAccounts();
    if (pendingAccounts.isEmpty) return 0;

    List<String> syncedAccounts = [];
    List<String> failedAccounts = [];

    for (String accountJson in pendingAccounts) {
      try {
        Map<String, dynamic> account = jsonDecode(accountJson);
        Map<String, dynamic> userData = account['userData'];

        UserCredential userCredential;
        try {
          userCredential = await _remote.createUserWithEmailPassword(
            email: userData['email'],
            password: userData['password'],
          );
        } on FirebaseAuthException catch (e) {
          if (e.code != 'email-already-in-use') rethrow;
          // حساب حقيقي أُنشئ في محاولة سابقة وفشلت خطوة لاحقة — نستكمل
          // العملية بدلاً من الالتصاق في حلقة إعادة المحاولة.
          userCredential = await _remote.signInWithEmailPassword(
            email: userData['email'],
            password: userData['password'],
          );
        }

        final String userId = userCredential.user!.uid;
        await userCredential.user?.updateDisplayName(userData['fullName']);

        // إرسال رسالة التحقق من البريد عند إنشاء الحساب (لا يوقف الاكتمال)
        try {
          await sendEmailVerification();
        } catch (_) {}

        await _remote.saveSyncedProfile(userId, userData);

        syncedAccounts.add(accountJson);
      } catch (e) {
        failedAccounts.add(accountJson);
      }
    }

    // تحديث القائمة المعلقة
    await _local.setPendingAccounts(failedAccounts);
    return syncedAccounts.length;
  }
}