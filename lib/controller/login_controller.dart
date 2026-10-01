// ignore_for_file: avoid_print
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:fkra/model/login_model.dart';
import 'package:fkra/services/activity_service.dart';
import 'package:fkra/services/account_status_service.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:fkra/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginController extends ChangeNotifier {
  final LoginModel _model = LoginModel();

  // حالة الواجهة
  bool isLoading = false;
  bool isOffline = false;

  // حالة التحقق من البريد
  bool _emailNotVerified = false;
  bool get emailNotVerified => _emailNotVerified;

  // حالة إعادة إرسال رسالة التحقق
  bool _isResendingVerification = false;
  bool get isResendingVerification => _isResendingVerification;
  String? _verificationMessage;
  String? get verificationMessage => _verificationMessage;
  DateTime? _lastVerificationSend;

  // متحكمات الحقول
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // مفتاح النموذج
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  LoginController() {
    _init();
  }

  Future<void> _init() async {
    await checkConnectivity();
    await syncOfflineLogins();
  }

  // ========== التحقق من الاتصال ==========
  Future<void> checkConnectivity() async {
    final hasInternet = await _model.hasInternet();
    isOffline = !hasInternet;
    notifyListeners();
  }

  // ========== مزامنة محاولات تسجيل الدخول المعلقة ==========
  Future<void> syncOfflineLogins() async {
    final pendingLogins = await _model.getPendingLogins();
    if (pendingLogins.isEmpty) return;

    final bool hasInternet = await _model.hasInternet();
    if (!hasInternet) return;

    String? userId;
    String? email;
    final List<int> processedIndexes = [];

    for (var i = 0; i < pendingLogins.length; i++) {
      final loginData = pendingLogins[i];
      try {
        final user = await _model.loginWithEmailAndPassword(
          loginData['email'],
          loginData['password'],
        );
        if (user != null) {
          await user.reload();
          final updatedUser = user;
          if (updatedUser.emailVerified) {
            // فحص حالة الحساب قبل حفظ الجلسة (مهما كان مالكاً أو مفوّضاً).
            // `unknown` لا يحفظ جلسة: محاولة قديمة بلا اتصال لا يجوز أن
            // تُعيد بناء جلسة لم يُتحقق منها.
            final accessState =
                await AccountStatusService.instance.checkUid(updatedUser.uid);
            if (accessState != AccountAccessState.active) {
              await _model.signOut();
            } else {
              userId = updatedUser.uid;
              email = loginData['email'];
              await _model.saveSessionLocally(userId, email!);
            }
          }
        }
      } catch (e) {
        print('خطأ في مزامنة تسجيل الدخول: $e');
      }
      // المحاولة اكتملت (نجحت أو فشلت نهائياً) → لا تُعاد محاولتها مستقبلاً
      processedIndexes.add(i);
    }

    // إبقاء ما لم تُعالج فقط — لا تُمسح بقية المحاولات (إصلاح لفقدان بيانات).
    if (processedIndexes.isNotEmpty) {
      final remaining = <Map<String, dynamic>>[];
      for (var i = 0; i < pendingLogins.length; i++) {
        if (!processedIndexes.contains(i)) remaining.add(pendingLogins[i]);
      }
      await _model.savePendingLogins(remaining);
    }

    if (userId != null && email != null) {
      // سيتم التعامل مع نجاح المزامنة في الـ View
      _pendingSyncSuccess = userId;
    }
    notifyListeners();
  }

  String? _pendingSyncSuccess;
  String? get pendingSyncSuccess => _pendingSyncSuccess;
  void clearPendingSyncSuccess() {
    _pendingSyncSuccess = null;
    notifyListeners();
  }

  // ========== دوال التحقق ==========
  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return "البريد الالكتروني لا يمكن ان يكون فارغ";
    } else if (value.length < 4) {
      return "البريد الالكتروني يجب ان يكون اكثر من 4 حروف";
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return "كلمة السر لا يمكن ان تكون فارغة";
    } else if (value.length < 6) {
      return "كلمة السر يجب ان تكون اكثر من 6 حروف";
    }
    return null;
  }

  bool validateForm() {
    return formKey.currentState?.validate() ?? false;
  }

  // ========== معالجة تسجيل الدخول ==========
  Future<String?> handleLogin(BuildContext context) async {
    if (isLoading) return null;

    if (!validateForm()) {
      return 'validation_error';
    }

    isLoading = true;
    _emailNotVerified = false;
    _verificationMessage = null;
    notifyListeners();

    final bool hasInternet = await _model.hasInternet();

    if (!hasInternet) {
      // حفظ محاولة تسجيل الدخول للمزامنة لاحقاً
      await _model.saveOfflineLoginAttempt(
        emailController.text.trim(),
        passwordController.text.trim(),
      );

      isLoading = false;
      notifyListeners();
      return 'offline';
    }

    // تسجيل الدخول عبر الإنترنت
    final user = await _model.loginWithEmailAndPassword(
      emailController.text.trim(),
      passwordController.text.trim(),
    );

    if (user != null) {
      // إعادة تحميل بيانات المستخدم للحصول على أحدث حالة emailVerified
      await user.reload();
      final updatedUser = user;

      // ⚠️ فحص حالة الحساب يتم هنا قبل أي تفريع (مالك / مفوّض).
      // كان داخل فرع المالك فقط، فحساب المفوّض الموقوف كان يدخل بلا فحص.
      //
      //Fail-closed: `unknown` (تعذّر قراءة الحالة من الخادم) لا يُعامَل
      //كنشط. قبل هذا كان `isAccountBlocked` يُرجع false عند أي فشل شبكة،
      //فأدخل الموقوف فعلاً بلا إنترنت أو انقطاع قراءة.
      final accessState = await AccountStatusService.instance
          .checkUid(updatedUser.uid)
          .timeout(const Duration(seconds: 8), onTimeout: () {
        // انتهاء المهلة = لا تأكيد ⇒ يُمنع الدخول، ويبقى السبب منطقياً.
        print('انتهت مهلة التحقق من حالة الحساب — يُمنع الدخول');
        return AccountAccessState.unknown;
      });
      if (accessState == AccountAccessState.suspended) {
        await _model.signOut();
        isLoading = false;
        notifyListeners();
        return 'account_blocked';
      }
      if (accessState == AccountAccessState.unknown) {
        await _model.signOut();
        isLoading = false;
        notifyListeners();
        return 'account_status_unverifiable';
      }

      // حسم الجلسة كمالك أو كمستخدم تابع فور نجاح المصادقة
        await MemberSessionService.instance.resolveForCurrentUser();
        final session = MemberSessionService.instance;

        if (session.isSubUser) {
          // الحساب الموقوف أو المحذوف على مستوى العضوية ممنوع من الدخول
          final member = session.member;
          if (member != null && member.status != 'active') {
            await _model.signOut();
            isLoading = false;
            notifyListeners();
            return 'account_blocked';
          }
          await _model.saveSessionLocally(
              updatedUser.uid, updatedUser.email ?? emailController.text.trim());
          isLoading = false;
          notifyListeners();
          await ActivityService.record(
              userId: updatedUser.uid, isLogin: true, method: 'email');
          await AnalyticsService.instance.logLogin(method: 'email');
          FirebaseUsageTracker.instance.recordEmailLogin();
          return updatedUser.uid;
        }

        // المستخدم مالك للحساب
        if (updatedUser.emailVerified) {
          await _model.saveSessionLocally(
              updatedUser.uid, updatedUser.email ?? emailController.text.trim());
          isLoading = false;
          notifyListeners();
          await ActivityService.record(
              userId: updatedUser.uid, isLogin: true, method: 'email');
          await AnalyticsService.instance.logLogin(method: 'email');
          FirebaseUsageTracker.instance.recordEmailLogin();
          return updatedUser.uid;
        } else {
          // البريد غير موثق وهو مالك → إرسال رسالة تحقق والانتقال لشاشة التحقق
          _emailNotVerified = true;
          _verificationMessage = null;
          final sent = await _model.sendVerificationEmail();
          if (sent) {
            _verificationMessage = 'تم إرسال رسالة التحقق إلى بريدك الإلكتروني';
          }
          isLoading = false;
          notifyListeners();
          return 'email_not_verified';
        }
    } else {
      // الحساب معطّل على مستوى Firebase Auth (إيقاف من لوحة المدير):
      // نعرض رسالة الإيقاف بدل خطأ عام.
      if (_model.lastAuthErrorCode == 'user-disabled') {
        await _model.signOut();
        isLoading = false;
        notifyListeners();
        return 'account_blocked';
      }
      isLoading = false;
      notifyListeners();
      return 'login_failed';
    }
  }

  // ========== تسجيل الدخول بواسطة Google ==========
  Future<String?> handleGoogleLogin(BuildContext context) async {
    if (isLoading) return null;

    isLoading = true;
    notifyListeners();

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // المستخدم ألغى عملية تسجيل الدخول
        isLoading = false;
        notifyListeners();
        return 'google_cancelled';
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final user = await _model.signInWithGoogle(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      if (user != null) {
        // فحص ما إذا كان الحساب معلّقاً من لوحة المدير — بنفسي المنطق
        // الفاشل-المغلق في مسار البريد: `unknown` يمنع الدخول أيضاً.
        final accessState = await AccountStatusService.instance
            .checkUid(user.uid)
            .timeout(const Duration(seconds: 8), onTimeout: () {
          print('انتهت مهلة التحقق من حالة الحساب (Google) — يُمنع الدخول');
          return AccountAccessState.unknown;
        });
        if (accessState == AccountAccessState.suspended) {
          await _model.signOut();
          isLoading = false;
          notifyListeners();
          return 'account_blocked';
        }
        if (accessState == AccountAccessState.unknown) {
          await _model.signOut();
          isLoading = false;
          notifyListeners();
          return 'account_status_unverifiable';
        }
        // حسابات Google تعتبر بريدها موثقاً من مزود Google
        // السماح بالدخول مباشرة دون فحص emailVerified
        // تعبئة المعلومات المتوفرة من Google (الاسم/البريد/الصورة) في بروفايل
        // المستخدم كي لا تظهر الإعدادات "غير محدد"
        await _model.seedProfileFromGoogle(
          uid: user.uid,
          displayName: googleUser.displayName,
          email: googleUser.email,
          photoURL: googleUser.photoUrl ?? user.photoURL,
        );
        await _model.saveSessionLocally(user.uid, user.email ?? '');
        isLoading = false;
        notifyListeners();
        await ActivityService.record(userId: user.uid, isLogin: true, method: 'google');
        await AnalyticsService.instance.logLogin(method: 'google');
        FirebaseUsageTracker.instance.recordGoogleLogin();
        return user.uid;
      } else {
        isLoading = false;
        notifyListeners();
        return 'login_failed';
      }
    } on PlatformException catch (e) {
      print('خطأ المنصة أثناء تسجيل الدخول بـ Google: ${e.message}');
      isLoading = false;
      notifyListeners();
      return 'google_error';
    } catch (e) {
      // كان يقابل FirebaseAuthException سابقاً: نفحص كود الخطأ المخزَّن من
      // طبقة البيانات (مثل user-disabled) ونعرض رسالة الإيقاف المناسبة.
      print('خطأ أثناء تسجيل الدخول بـ Google: $e');
      if (_model.lastAuthErrorCode == 'user-disabled') {
        await _model.signOut();
        isLoading = false;
        notifyListeners();
        return 'account_blocked';
      }
      isLoading = false;
      notifyListeners();
      return 'google_error';
    }
  }

  // ========== إعادة إرسال رسالة التحقق ==========
  Future<void> resendEmailVerification() async {
    // منع إعادة الإرسال بشكل متكرر (حد أدنى 30 ثانية بين كل محاولتين)
    if (_lastVerificationSend != null &&
        DateTime.now().difference(_lastVerificationSend!) < const Duration(seconds: 30)) {
      _verificationMessage = 'يرجى الانتظار قليلاً قبل إعادة إرسال رسالة التحقق';
      notifyListeners();
      return;
    }

    _isResendingVerification = true;
    _verificationMessage = null;
    notifyListeners();

    final bool success = await _model.resendEmailVerification();

    _isResendingVerification = false;
    _lastVerificationSend = DateTime.now();
    _verificationMessage = success
        ? 'تم إرسال رسالة التحقق إلى بريدك الإلكتروني'
        : 'حدث خطأ أثناء إرسال رسالة التحقق. حاول مرة أخرى.';
    notifyListeners();
  }

  // ========== فحص ما إذا تم التحقق من البريد ==========
  Future<bool> checkEmailVerified() async {
    final bool isVerified = await _model.reloadUser();

    if (isVerified) {
      FirebaseUsageTracker.instance.recordVerification();
      _emailNotVerified = false;
      _verificationMessage = null;
    }
    notifyListeners();
    return isVerified;
  }

  // ========== تسجيل الخروج ==========
  Future<void> signOut() async {
    await _model.signOut();
    _emailNotVerified = false;
    _verificationMessage = null;
    notifyListeners();
  }

  // ========== تبديل رؤية كلمة المرور ==========
  void togglePasswordVisibility() {
    // سنقوم بإدارة هذا في الـ View باستخدام StatefulBuilder
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}