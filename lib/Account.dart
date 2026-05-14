import 'dart:async';
import 'package:fkra/main.dart';
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

class Accounts extends StatefulWidget {
  @override
  State<Accounts> createState() => _AccountsState();
}

class _AccountsState extends State<Accounts> {
  // لتخزين بيانات الحقول وإدارتها

  final TextEditingController nameController = TextEditingController();
  final TextEditingController businessNameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  // مفتاح النموذج للتحقق من صحة الحقول
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  // حالات التحكم في واجهة المستخدم والمزامنة
  bool isPasswordVisible = false;
  bool isConfirmPasswordVisible = false;
  bool isLoading = false;
  bool isOffline = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _checkPendingAccounts();
  }

  // التحقق من الاتصال بالإنترنت
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

// تحديث حالة الاتصال بالإنترنت
  Future<void> _checkConnectivity() async {
    final hasInternet = await _hasInternet();
    if (mounted) {
      setState(() {
        isOffline = !hasInternet;
      });
    }
  }

  // التحقق من وجود حسابات معلقة
  Future<void> _checkPendingAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingAccounts = prefs.getStringList('pending_accounts') ?? [];
    if (pendingAccounts.isNotEmpty && !isOffline) {
      await _syncPendingAccounts();
    }
  }

  // حفظ الحساب محلياً
  Future<void> _saveAccountLocally(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> pendingAccounts =
          prefs.getStringList('pending_accounts') ?? [];

      Map<String, dynamic> pendingData = {
        'userData': userData,
        'timestamp': DateTime.now().toIso8601String(),
        'email': userData['email'],
        'fullName': userData['fullName'],
      };

      pendingAccounts.add(jsonEncode(pendingData));
      await prefs.setStringList('pending_accounts', pendingAccounts);

      if (mounted) {
        AwesomeDialog(
          context: context,
          dialogType: DialogType.info,
          animType: AnimType.scale,
          title: ' تم الحفظ محلياً',
          desc:
              'لا يوجد اتصال بالإنترنت. تم حفظ بياناتك محلياً وسيتم إنشاء حسابك تلقائياً عند توفر الاتصال.',
          btnOkText: 'حسناً',
          btnOkOnPress: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => LoginScreen()),
            );
          },
        ).show();
      }
    } catch (e) {
      print('خطأ في الحفظ المحلي: $e');
    }
  }

  // مزامنة الحسابات المعلقة مع Firebase
  Future<void> _syncPendingAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingAccounts = prefs.getStringList('pending_accounts') ?? [];

    if (pendingAccounts.isEmpty) return;

    List<String> syncedAccounts = [];
    List<String> failedAccounts = [];

    for (String accountJson in pendingAccounts) {
      try {
        Map<String, dynamic> account = jsonDecode(accountJson);
        Map<String, dynamic> userData = account['userData'];

        // إنشاء الحساب في Firebase
        UserCredential userCredential =
            await _auth.createUserWithEmailAndPassword(
          email: userData['email'],
          password: userData['password'],
        );

        final String userId = userCredential.user!.uid;
        await userCredential.user?.updateDisplayName(userData['fullName']);

        // حفظ البيانات في Firestore
        Map<String, dynamic> firestoreData = {
          'userId': userId,
          'fullName': userData['fullName'],
          'businessName': userData['businessName'],
          'phoneNumber': userData['phoneNumber'],
          'email': userData['email'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await _firestore.collection('users').doc(userId).set(firestoreData);

        syncedAccounts.add(accountJson);
      } catch (e) {
        print('خطأ في مزامنة الحساب: $e');
        failedAccounts.add(accountJson);
      }
    }

    // تحديث قائمة الحسابات المعلقة
    final remainingAccounts = [...failedAccounts];
    await prefs.setStringList('pending_accounts', remainingAccounts);

    // عرض إشعار المزامنة
    if (mounted && syncedAccounts.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم مزامنة ${syncedAccounts.length} حساب بنجاح'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  String? validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'يرجى إدخال الاسم الكامل';
    }
    if (value.length < 3) {
      return 'الاسم يجب أن يكون 3 أحرف على الأقل';
    }
    if (value.length > 50) {
      return 'الاسم طويل جداً';
    }
    return null;
  }

  String? validateBusinessName(String? value) {
    if (value == null || value.isEmpty) {
      return 'يرجى إدخال اسم النشاط التجاري';
    }
    if (value.length < 3) {
      return 'اسم النشاط يجب أن يكون 3 أحرف على الأقل';
    }
    return null;
  }

  String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'يرجى إدخال رقم الهاتف';
    }
    String phone = value.replaceAll(RegExp(r'[\s\-]'), '');
    if (!RegExp(r'^[0-9]+$').hasMatch(phone)) {
      return 'رقم الهاتف يجب أن يحتوي على أرقام فقط';
    }
    if (phone.length < 9 || phone.length > 12) {
      return 'رقم الهاتف غير صحيح (يجب أن يكون 9-12 رقم)';
    }
    return null;
  }

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'يرجى إدخال البريد الإلكتروني';
    }
    String emailPattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    RegExp regex = RegExp(emailPattern);
    if (!regex.hasMatch(value)) {
      return 'البريد الإلكتروني غير صحيح (example@domain.com)';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
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
    return null;
  }

  String? validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'يرجى تأكيد كلمة المرور';
    }
    if (value != passwordController.text) {
      return 'كلمة المرور غير متطابقة';
    }
    return null;
  }

  bool validateAndSave() {
    final form = _formKey.currentState;
    if (form != null) {
      if (form.validate()) {
        return true;
      } else {
        AwesomeDialog(
          context: context,
          dialogType: DialogType.warning,
          animType: AnimType.scale,
          title: 'تنبيه',
          desc: 'يرجى تصحيح الأخطاء في الحقول المحددة',
          btnCancelText: 'حسناً',
          btnCancelOnPress: () {},
        ).show();
        return false;
      }
    }
    return false;
  }

  Future<void> saveUserDataToFirestore(String userId) async {
    try {
      Map<String, dynamic> userData = {
        'userId': userId,
        'fullName': nameController.text.trim(),
        'businessName': businessNameController.text.trim(),
        'phoneNumber': phoneController.text.trim(),
        'email': emailController.text.trim().toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _firestore.collection('users').doc(userId).set(userData);
    } catch (e) {
      throw Exception('فشل في حفظ بيانات المستخدم');
    }
  }

  Future<void> createAccountWithFirebase() async {
    if (!validateAndSave()) return;

    setState(() => isLoading = true);

    // تجهيز بيانات المستخدم
    Map<String, dynamic> userData = {
      'fullName': nameController.text.trim(),
      'businessName': businessNameController.text.trim(),
      'phoneNumber': phoneController.text.trim(),
      'email': emailController.text.trim().toLowerCase(),
      'password': passwordController.text.trim(),
    };

    final bool hasInternet = await _hasInternet();

    if (!hasInternet) {
      // حفظ البيانات محلياً
      await _saveAccountLocally(userData);
      setState(() => isLoading = false);

      // تنظيف الحقول
      _clearForm();
      return;
    }

    // هناك إنترنت - إنشاء الحساب مباشرة
    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: userData['email'],
        password: userData['password'],
      );

      final String userId = userCredential.user!.uid;

      await userCredential.user?.updateDisplayName(userData['fullName']);
      await userCredential.user?.reload();
      await saveUserDataToFirestore(userId);

      if (mounted) setState(() => isLoading = false);

      AwesomeDialog(
        context: context,
        dialogType: DialogType.success,
        animType: AnimType.scale,
        title: '✅ تم انشاء الحساب بنجاح',
        desc:
            'تم إنشاء حسابك وحفظ بياناتك بنجاح.\nسيتم إرسال بريد تأكيد إلى بريدك الإلكتروني.',
        btnOkText: 'تسجيل الدخول',
        btnOkOnPress: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => LoginScreen()),
          );
        },
      ).show();

      // تنظيف الحقول
      _clearForm();
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => isLoading = false);

      String errorMessage = '';
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage =
              'هذا البريد الإلكتروني مستخدم بالفعل. الرجاء استخدام بريد آخر أو تسجيل الدخول.';
          break;
        case 'invalid-email':
          errorMessage = 'البريد الإلكتروني غير صحيح.';
          break;
        case 'weak-password':
          errorMessage =
              'كلمة المرور ضعيفة جداً. الرجاء استخدام كلمة مرور أقوى.';
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
      if (mounted) setState(() => isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Center(
          child: Text(
            'انشاء حساب جديد',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        elevation: 0,
        backgroundColor: colorScheme.surface,
        actions: [
          // إظهار أيقونة حالة الاتصال
          if (isOffline)
            Padding(
              padding: EdgeInsets.all(8),
              child: Tooltip(
                message: 'لا يوجد اتصال بالإنترنت - سيتم حفظ البيانات محلياً',
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange, size: 18),
                      SizedBox(width: 4),
                      Text(
                        'غير متصل',
                        style: TextStyle(color: Colors.orange, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // إشعار وضع عدم الاتصال
                  if (isOffline)
                    Container(
                      margin: EdgeInsets.only(bottom: 20),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off, color: Colors.orange),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'لا يوجد اتصال بالإنترنت. سيتم حفظ بياناتك محلياً وإنشاء حسابك تلقائياً عند توفر الاتصال.',
                              style: TextStyle(
                                  color: Colors.orange[700], fontSize: 12),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),

                  _buildSectionTitle("المعلومات الشخصية", colorScheme),
                  SizedBox(height: 10),
                  Divider(color: colorScheme.outline, thickness: 1),
                  SizedBox(height: 10),

                  _buildFormField(
                    label: "الاسم الكامل *",
                    controller: nameController,
                    validator: validateFullName,
                    hintText: 'ادخل اسمك الكامل',
                    icon: Icons.person_outline,
                    colorScheme: colorScheme,
                  ),
                  SizedBox(height: 20),

                  _buildFormField(
                    label: "اسم النشاط التجاري *",
                    controller: businessNameController,
                    validator: validateBusinessName,
                    hintText: 'مثال : مؤسسة تساهيل',
                    icon: Icons.business_outlined,
                    colorScheme: colorScheme,
                  ),
                  SizedBox(height: 20),

                  _buildFormField(
                    label: "رقم الهاتف *",
                    controller: phoneController,
                    validator: validatePhone,
                    hintText: '7xxxxxxxx',
                    icon: Icons.phone_android_outlined,
                    keyboardType: TextInputType.phone,
                    colorScheme: colorScheme,
                  ),
                  SizedBox(height: 30),

                  _buildSectionTitle("بيانات الحساب", colorScheme),
                  SizedBox(height: 10),
                  Divider(color: colorScheme.outline, thickness: 1),
                  SizedBox(height: 20),

                  _buildFormField(
                    label: "البريد الالكتروني *",
                    controller: emailController,
                    validator: validateEmail,
                    hintText: 'example@email.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    colorScheme: colorScheme,
                  ),
                  SizedBox(height: 20),

                  _buildPasswordField(
                    label: "كلمة السر *",
                    controller: passwordController,
                    validator: validatePassword,
                    hintText: '6 أحرف على الأقل، مع حرف كبير ورقم',
                    isVisible: isPasswordVisible,
                    onToggle: () =>
                        setState(() => isPasswordVisible = !isPasswordVisible),
                    colorScheme: colorScheme,
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 8, right: 12),
                    child: Text(
                      'يجب أن تحتوي كلمة المرور على: 6 أحرف على الأقل، حرف كبير، حرف صغير، ورقم',
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(height: 20),

                  _buildPasswordField(
                    label: "تأكيد كلمة السر *",
                    controller: confirmPasswordController,
                    validator: validateConfirmPassword,
                    hintText: 'اعد كتابة كلمة السر للتأكيد',
                    isVisible: isConfirmPasswordVisible,
                    onToggle: () => setState(() =>
                        isConfirmPasswordVisible = !isConfirmPasswordVisible),
                    colorScheme: colorScheme,
                  ),
                  SizedBox(height: 30),

                  Center(
                    child: ElevatedButton(
                      onPressed: isLoading ? null : createAccountWithFirebase,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(300, 50),
                        padding: EdgeInsets.all(10),
                        backgroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: colorScheme.onPrimary,
                                strokeWidth: 2,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isOffline)
                                  Icon(Icons.save,
                                      size: 20, color: colorScheme.onPrimary),
                                if (isOffline) SizedBox(width: 8),
                                Text(
                                  isOffline ? 'حفظ محلياً' : 'انشاء حساب',
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                                builder: (context) => LoginScreen()),
                          );
                        },
                        child: Text(
                          'تسجيل الدخول',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        "هل لديك حساب بالفعل؟",
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: Card(
                  elevation: 5,
                  color: colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              colorScheme.primary),
                        ),
                        SizedBox(height: 15),
                        Text(
                          isOffline
                              ? 'جاري الحفظ محلياً...'
                              : 'جاري إنشاء الحساب...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          isOffline
                              ? 'سيتم إنشاء الحساب عند توفر الاتصال'
                              : 'يرجى الانتظار',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        color: colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    required ColorScheme colorScheme,
  }) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: 10),
        TextFormField(
          controller: controller,
          textAlign: TextAlign.right,
          keyboardType: keyboardType,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.outline),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            errorBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.error, width: 1),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.error, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            prefixIcon: Icon(icon, color: colorScheme.onSurfaceVariant),
            errorStyle: TextStyle(fontSize: 12, color: colorScheme.error),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    required String hintText,
    required bool isVisible,
    required VoidCallback onToggle,
    required ColorScheme colorScheme,
  }) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: 10),
        TextFormField(
          controller: controller,
          textAlign: TextAlign.right,
          obscureText: !isVisible,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.outline),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            errorBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.error, width: 1),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.error, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            suffixIcon: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(10),
              child: Icon(
                isVisible ? Icons.visibility : Icons.visibility_off,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            errorStyle: TextStyle(fontSize: 12, color: colorScheme.error),
          ),
        ),
      ],
    );
  }
}
