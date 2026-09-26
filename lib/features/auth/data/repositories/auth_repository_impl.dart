// lib/features/auth/data/repositories/auth_repository_impl.dart
// تنفيذ عقد AuthRepository بفصل المصادر: Firebase في المصدر البعيد،
// SharedPreferences في المصدر المحلي، والتحقق من الاتصال في الخدمة الموحدة.
// لا تحمل الطبقات الأعلى أي فكرة عن هذه المصادر.
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/network/connectivity_service.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_datasource.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl._();
  static final AuthRepositoryImpl instance = AuthRepositoryImpl._();

  final AuthRemoteDataSource _remote = AuthRemoteDataSource.instance;
  final AuthLocalDataSource _local = AuthLocalDataSource.instance;

  @override
  Future<bool> hasInternet() => ConnectivityService.hasInternet();

  @override
  Future<void> saveSessionLocally(String userId, String email) =>
      _local.saveSessionLocally(userId, email);

  @override
  Future<void> saveOfflineLoginAttempt(String email, String password) =>
      _local.saveOfflineLoginAttempt(email, password);

  @override
  Future<List<Map<String, dynamic>>> getPendingLogins() =>
      _local.getPendingLogins();

  @override
  Future<void> clearPendingLogins() => _local.clearPendingLogins();

  @override
  Future<void> savePendingLogins(List<Map<String, dynamic>> logs) =>
      _local.savePendingLogins(logs);

  @override
  String? get lastAuthErrorCode => _remote.lastAuthErrorCode;

  @override
  Future<AuthSession?> loginWithEmailAndPassword(
      String email, String password) async {
    final User? user = await _remote.loginWithEmailAndPassword(email, password);
    if (user == null) return null;
    return AuthSession(
      uid: user.uid,
      email: user.email ?? '',
      emailVerified: user.emailVerified,
    );
  }

  @override
  Future<AuthSession?> signInWithGoogleCredential({
    required String? accessToken,
    required String? idToken,
  }) async {
    final User? user = await _remote.signInWithGoogleCredential(
      accessToken: accessToken,
      idToken: idToken,
    );
    if (user == null) return null;
    return AuthSession(
      uid: user.uid,
      email: user.email ?? '',
      emailVerified: user.emailVerified,
    );
  }

  @override
  String? get currentUserEmail => _remote.currentUserEmail;

  @override
  Future<bool> isEmailVerified() => _remote.isEmailVerified();

  @override
  Future<bool> resendEmailVerification() => _remote.resendEmailVerification();

  @override
  Future<bool> sendVerificationEmail() => _remote.sendVerificationEmail();

  @override
  Future<bool> isAccountBlocked(String uid) => _remote.isAccountBlocked(uid);

  @override
  Future<void> seedProfileFromGoogle({
    required String uid,
    String? displayName,
    String? email,
    String? photoURL,
  }) =>
      _remote.seedProfileFromGoogle(
        uid: uid,
        displayName: displayName,
        email: email,
        photoURL: photoURL,
      );

  @override
  Future<bool> reloadUser() => _remote.reloadUser();

  @override
  Future<void> clearSessionPrefs() => _local.clearSessionPrefs();

  @override
  Future<void> signOutPlatform() => _remote.signOutPlatform();

  @override
  Future<void> signOut() async {
    await _remote.signOutPlatform();
    await _local.clearSessionPrefs();
  }
}