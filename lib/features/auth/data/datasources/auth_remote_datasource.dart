// lib/features/auth/data/datasources/auth_remote_datasource.dart
// المسؤول الوحيد عن الاتصال بمصادقة Firebase ووثيقة المستخدم في Firestore
// وتسجيل الخروج من Google. منقولة حرفياً من LoginModel القديم بنفس السلوك
// ودون أي تغيير في النتائج أو رسائل الأخطاء (أبعِد `print` فقط).
//
// لا يمكن الوصول إلى هذا الكلاس من خارج طبقة البيانات (Repositories).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:fkra/services/account_status_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource._();
  static final AuthRemoteDataSource instance = AuthRemoteDataSource._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// آخر كود خطأ Auth (مثل user-disabled) ليستخدمه المتحكم لعرض الرسالة الصحيحة.
  String? lastAuthErrorCode;

  Future<User?> loginWithEmailAndPassword(
      String email, String password) async {
    lastAuthErrorCode = null;
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } on FirebaseAuthException catch (e) {
      lastAuthErrorCode = e.code;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// تسجيل الدخول بخطوة اختيار حساب Google (Credential مبني من رموز GoogleSignIn).
  /// يخزّن كود الخطأ في lastAuthErrorCode ثم يعيد الرمي ليُعالجه المتحكم كما
  /// كان يفعل سابقاً مع FirebaseAuthException.
  Future<User?> signInWithGoogleCredential({
    required String? accessToken,
    required String? idToken,
  }) async {
    lastAuthErrorCode = null;
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: accessToken,
      idToken: idToken,
    );
    try {
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      lastAuthErrorCode = e.code;
      rethrow;
    }
  }

  /// البريد الإلكتروني للمستخدم الحالي (منحىً ومعرّى) أو null.
  String? get currentUserEmail =>
      _auth.currentUser?.email?.trim().toLowerCase();

  Future<bool> isEmailVerified() async {
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// إعادة إرسال رسالة التحقق (تُستخدم من شاشة التحقق).
  Future<bool> resendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// إرسال رسالة التحقق لحظة منع الدخول — يجب أن يبقى المستخدم مسجلاً لكي
  /// تعمل الإرسال (لا تُسجَّل خروجه قبل الإرسال).
  Future<bool> sendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// فحص ما إذا كان الحساب معلّقاً (حالة الحساب = users/{uid}.status).
  ///
  /// ⚠️ كان هنا `Source.serverAndCache` مع `catch → false`، أي أن كاشاً
  /// قديماً أو انقطاعاً قصيراً كانا يعنيان "غير مقيَّد" ⇒ تجاوز للتقييد.
  /// الآن القراءة من الخادم مباشرة عبر الخدمة الموحّدة، وعند تعذّر القراءة
  /// تُحفظ آخر حالة معروفة بدل افتراض السماح.
  Future<bool> isAccountBlocked(String uid) async {
    final state = await AccountStatusService.instance.checkUid(uid);
    return state == AccountAccessState.suspended;
  }

  /// تعبئة بروفايل المستخدم من بيانات Google (فجوات فقط لا تكتب فوق بياناته).
  Future<void> seedProfileFromGoogle({
    required String uid,
    String? displayName,
    String? email,
    String? photoURL,
  }) async {
    try {
      final ref = _firestore.collection('users').doc(uid);
      final doc = await ref.get(const GetOptions(source: Source.serverAndCache));
      FirebaseUsageTracker.instance.recordRead();
      if (!doc.exists) {
        await ref.set({
          'fullName': displayName ?? '',
          'email': email ?? '',
          'photoURL': photoURL ?? '',
          'userType': 'user',
          // يُكتب عند الإنشاء فقط؛ التحديثات محرّمة عليه (statusKeysTouched).
          'isActive': true,
          'lastLoginMethod': 'google',
          'lastLoginAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        FirebaseUsageTracker.instance.recordWrite();
        return;
      }
      final data = doc.data() ?? <String, dynamic>{};
      final updates = <String, dynamic>{
        'lastLoginMethod': 'google',
        'lastLoginAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (email != null && email.isNotEmpty && (data['email'] ?? '').toString().isEmpty) {
        updates['email'] = email;
      }
      if (displayName != null &&
          displayName.isNotEmpty &&
          (data['fullName'] ?? '').toString().isEmpty) {
        updates['fullName'] = displayName;
      }
      if (photoURL != null &&
          photoURL.isNotEmpty &&
          (data['photoURL'] ?? '').toString().isEmpty) {
        updates['photoURL'] = photoURL;
      }
      await ref.update(updates);
      FirebaseUsageTracker.instance.recordWrite();
    } catch (_) {
      // فشل التهيئة لا يمنع تسجيل الدخول — تُملأ البيانات عند المزامنة التالية.
    }
  }

  /// إعادة تحميل بيانات المستخدم والتحقق من البريد.
  Future<bool> reloadUser() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.reload();
        return _auth.currentUser?.emailVerified ?? false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// تسجيل الخروج من المنصات (Firebase + Google) — تسجيل الخروج من Google
  /// يضمن ظهور نافذة اختيار الحساب عند الدخول بحساب آخر.
  Future<void> signOutPlatform() async {
    await _auth.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // لا نوقف تسجيل الخروج بسبب فشل Google.
    }
  }
}