// lib/controllers/account_controller.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/model/account_model.dart';
import 'package:fkra/view/login_view.dart';
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';

class AccountController extends ChangeNotifier {
  final AccountModel _model = AccountModel();

  // Controllers للحقول
  final TextEditingController nameController = TextEditingController();
  final TextEditingController businessNameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  // حالة الـ UI
  bool isPasswordVisible = false;
  bool isConfirmPasswordVisible = false;
  bool isLoading = false;
  bool isOffline = false;

  AccountController() {
    _initialize();
  }

  Future<void> _initialize() async {
    await checkConnectivity();
    await checkPendingAccounts();
  }

  // تحديث حالة الاتصال
  Future<void> checkConnectivity() async {
    final hasInternet = await _model.hasInternet();
    isOffline = !hasInternet;
    notifyListeners();
  }

  // التحقق من وجود حسابات معلقة ومزامنتها
  Future<void> checkPendingAccounts() async {
    final pending = await _model.getPendingAccounts();
    if (pending.isNotEmpty && !isOffline) {
      final syncedCount = await _model.syncPendingAccounts();
      if (syncedCount > 0) {
        // يمكن إظهار SnackBar من خلال الـ View (سيتم تمرير context)
        // نترك ذلك للـ View
      }
    }
  }

  // دوال التحقق (تظل كما هي)
  String? validateFullName(String? value) {   if (value == null || value.isEmpty) {
      return 'يرجى إدخال الاسم الكامل';
    }
    if (value.length < 3) {
      return 'الاسم يجب أن يكون 3 أحرف على الأقل';
    }
    if (value.length > 50) {
      return 'الاسم طويل جداً';
    }
    return null; }
  String? validateBusinessName(String? value) {  if (value == null || value.isEmpty) {
      return 'يرجى إدخال اسم النشاط التجاري';
    }
    if (value.length < 3) {
      return 'اسم النشاط يجب أن يكون 3 أحرف على الأقل';
    }
    return null; }
  String? validatePhone(String? value) {  if (value == null || value.isEmpty) {
      return 'يرجى إدخال رقم الهاتف';
    }
    String phone = value.replaceAll(RegExp(r'[\s\-]'), '');
    if (!RegExp(r'^[0-9]+$').hasMatch(phone)) {
      return 'رقم الهاتف يجب أن يحتوي على أرقام فقط';
    }
    if (phone.length < 9 || phone.length > 12) {
      return 'رقم الهاتف غير صحيح (يجب أن يكون 9-12 رقم)';
    }
    return null; }  
  String? validateEmail(String? value) {  if (value == null || value.isEmpty) {
      return 'يرجى إدخال البريد الإلكتروني';
    }
    String emailPattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    RegExp regex = RegExp(emailPattern);
    if (!regex.hasMatch(value)) {
      return 'البريد الإلكتروني غير صحيح (example@domain.com)';
    }
    return null; }
  String? validatePassword(String? value) { if (value == null || value.isEmpty) {
      return 'يرجى إدخال كلمة المرور';
    }
    if (value.length < 6) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'كلمة المرور يجب أن تحتوي على حرف كبير واحد على الأقل';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'كلمة المرور يجب أن تحتوي على رقم واحد على الأقل';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'كلمة المرور يجب أن تحتوي على حرف صغير واحد على الأقل';
    }
    return null; }
  String? validateConfirmPassword(String? value) { if (value == null || value.isEmpty) {
      return 'يرجى تأكيد كلمة المرور';
    }
    if (value != passwordController.text) {
      return 'كلمة المرور غير متطابقة';
    }
    return null; }

  bool validateAndSave() {
    final form = formKey.currentState;
    if (form != null && form.validate()) {
      return true;
    }
    return false;
  }

  // تبديل رؤية كلمة المرور
  void togglePasswordVisibility() {
    isPasswordVisible = !isPasswordVisible;
    notifyListeners();
  }

  void toggleConfirmPasswordVisibility() {
    isConfirmPasswordVisible = !isConfirmPasswordVisible;
    notifyListeners();
  }

  // إنشاء حساب (يستدعى من الـ View)
  Future<void> createAccount(BuildContext context) async {
    if (!validateAndSave()) {
      AwesomeDialog(
        context: context,
        dialogType: DialogType.warning,
        animType: AnimType.scale,
        title: 'تنبيه',
        desc: 'يرجى تصحيح الأخطاء في الحقول المحددة',
        btnCancelText: 'حسناً',
        btnCancelOnPress: () {},
      ).show();
      return;
    }

    isLoading = true;
    notifyListeners();

    // تجهيز بيانات المستخدم
    Map<String, dynamic> userData = {
      'fullName': nameController.text.trim(),
      'businessName': businessNameController.text.trim(),
      'phoneNumber': phoneController.text.trim(),
      'email': emailController.text.trim().toLowerCase(),
      'password': passwordController.text.trim(),
    };

    final bool hasInternet = await _model.hasInternet();

    if (!hasInternet) {
      // حفظ محلياً
      await _model.saveAccountLocally(userData);
      isLoading = false;
      notifyListeners();
      _clearForm();

      AwesomeDialog(
        context: context,
        dialogType: DialogType.info,
        animType: AnimType.scale,
        title: 'تم الحفظ محلياً',
        desc: 'لا يوجد اتصال بالإنترنت. تم حفظ بياناتك محلياً وسيتم إنشاء حسابك تلقائياً عند توفر الاتصال.',
        btnOkText: 'حسناً',
        btnOkOnPress: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => LoginScreen()),
          );
        },
      ).show();
      return;
    }

    // هناك إنترنت → إنشاء الحساب
    try {
      UserCredential userCredential = await _model.createAccountWithEmailPassword(
        email: userData['email'],
        password: userData['password'],
      );

      final String userId = userCredential.user!.uid;
      await userCredential.user?.updateDisplayName(userData['fullName']);
      await userCredential.user?.reload();
      await _model.saveUserDataToFirestore(userId: userId, userData: userData);

      isLoading = false;
      notifyListeners();
      _clearForm();

      AwesomeDialog(
        context: context,
        dialogType: DialogType.success,
        animType: AnimType.scale,
        title: '✅ تم انشاء الحساب بنجاح',
        desc: 'تم إنشاء حسابك وحفظ بياناتك بنجاح.\nسيتم إرسال بريد تأكيد إلى بريدك الإلكتروني.',
        btnOkText: 'تسجيل الدخول',
        btnOkOnPress: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => LoginScreen()),
          );
        },
      ).show();

    } on FirebaseAuthException catch (e) {
      isLoading = false;
      notifyListeners();

      String errorMessage = '';
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'هذا البريد الإلكتروني مستخدم بالفعل. الرجاء استخدام بريد آخر أو تسجيل الدخول.';
          break;
        case 'invalid-email':
          errorMessage = 'البريد الإلكتروني غير صحيح.';
          break;
        case 'weak-password':
          errorMessage = 'كلمة المرور ضعيفة جداً. الرجاء استخدام كلمة مرور أقوى.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'عذراً، خدمة إنشاء الحساب غير مفعلة حالياً.';
          break;
        default:
          errorMessage = 'حدث خطأ: ${e.message}';
      }

      AwesomeDialog(
        context: context,
        dialogType: DialogType.error,
        animType: AnimType.scale,
        title: '❌ فشل إنشاء الحساب',
        desc: errorMessage,
        btnCancelText: 'حسناً',
        btnCancelOnPress: () {},
      ).show();
    } catch (e) {
      isLoading = false;
      notifyListeners();
      AwesomeDialog(
        context: context,
        dialogType: DialogType.error,
        animType: AnimType.scale,
        title: 'خطأ',
        desc: 'حدث خطأ غير متوقع: ${e.toString()}',
        btnCancelText: 'حسناً',
        btnCancelOnPress: () {},
      ).show();
    }
  }

  void _clearForm() {
    nameController.clear();
    businessNameController.clear();
    phoneController.clear();
    emailController.clear();
    passwordController.clear();
    confirmPasswordController.clear();
  }

  @override
  void dispose() {
    nameController.dispose();
    businessNameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}