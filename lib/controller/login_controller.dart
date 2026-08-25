// lib/controllers/login_controller.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/model/login_model.dart';
import 'package:flutter/material.dart';

class LoginController extends ChangeNotifier {
  final LoginModel _model = LoginModel();

  // حالة الواجهة
  bool isLoading = false;
  bool isOffline = false;

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

    for (var loginData in pendingLogins) {
      try {
        User? user = await _model.loginWithEmailAndPassword(
          loginData['email'],
          loginData['password'],
        );
        if (user != null) {
          userId = user.uid;
          email = loginData['email'];
          await _model.saveSessionLocally(userId, email!);
          break;
        }
      } catch (e) {
        print('خطأ في مزامنة تسجيل الدخول: $e');
      }
    }

    await _model.clearPendingLogins();

    if (userId != null && email != null) {
      // سيتم التعامل مع نجاح المزامنة في الـ View
      // نمرر النتيجة عبر notifyListeners أو نستخدم callback
      // سنستخدم خاصية لإعلام الـ View
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
    User? user = await _model.loginWithEmailAndPassword(
      emailController.text.trim(),
      passwordController.text.trim(),
    );

    isLoading = false;
    notifyListeners();

    if (user != null) {
      await _model.saveSessionLocally(user.uid, emailController.text.trim());
      return user.uid;
    } else {
      return 'login_failed';
    }
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