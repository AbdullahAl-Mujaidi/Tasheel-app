// lib/views/account_view.dart
import 'package:fkra/controller/account_controller.dart';
import 'package:fkra/view/login_view.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Accounts extends StatelessWidget {
  const Accounts({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ChangeNotifierProvider(
      create: (_) => AccountController(),
      child: Consumer<AccountController>(
        builder: (context, controller, child) {
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
                if (controller.isOffline)
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Tooltip(
                      message: 'لا يوجد اتصال بالإنترنت - سيتم حفظ البيانات محلياً',
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
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
                    key: controller.formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (controller.isOffline)
                          Container(
                            margin: EdgeInsets.only(bottom: 20),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.wifi_off, color: Colors.orange),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'لا يوجد اتصال بالإنترنت. سيتم حفظ بياناتك محلياً وإنشاء حسابك تلقائياً عند توفر الاتصال.',
                                    style: TextStyle(color: Colors.orange[700], fontSize: 12),
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
                          controller: controller.nameController,
                          validator: controller.validateFullName,
                          hintText: 'ادخل اسمك الكامل',
                          icon: Icons.person_outline,
                          colorScheme: colorScheme,
                        ),
                        SizedBox(height: 20),
                        _buildFormField(
                          label: "اسم النشاط التجاري *",
                          controller: controller.businessNameController,
                          validator: controller.validateBusinessName,
                          hintText: 'مثال : مؤسسة تسهيل',
                          icon: Icons.business_outlined,
                          colorScheme: colorScheme,
                        ),
                        SizedBox(height: 20),
                        _buildFormField(
                          label: "رقم الهاتف *",
                          controller: controller.phoneController,
                          validator: controller.validatePhone,
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
                          controller: controller.emailController,
                          validator: controller.validateEmail,
                          hintText: 'example@email.com',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          colorScheme: colorScheme,
                        ),
                        SizedBox(height: 20),
                        _buildPasswordField(
                          label: "كلمة السر *",
                          controller: controller.passwordController,
                          validator: controller.validatePassword,
                          hintText: '6 أحرف على الأقل، مع حرف كبير ورقم',
                          isVisible: controller.isPasswordVisible,
                          onToggle: controller.togglePasswordVisibility,
                          colorScheme: colorScheme,
                        ),
                        Padding(
                          padding: EdgeInsets.only(top: 8, right: 12),
                          child: Text(
                            'يجب أن تحتوي كلمة المرور على: 6 أحرف على الأقل، حرف كبير، حرف صغير، ورقم',
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        SizedBox(height: 20),
                        _buildPasswordField(
                          label: "تأكيد كلمة السر *",
                          controller: controller.confirmPasswordController,
                          validator: controller.validateConfirmPassword,
                          hintText: 'اعد كتابة كلمة السر للتأكيد',
                          isVisible: controller.isConfirmPasswordVisible,
                          onToggle: controller.toggleConfirmPasswordVisibility,
                          colorScheme: colorScheme,
                        ),
                        SizedBox(height: 30),
                        Center(
                          child: ElevatedButton(
                            onPressed: controller.isLoading ? null : () => controller.createAccount(context),
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
                            child: controller.isLoading
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
                                      if (controller.isOffline)
                                        Icon(Icons.save, size: 20, color: colorScheme.onPrimary),
                                      if (controller.isOffline) SizedBox(width: 8),
                                      Text(
                                        controller.isOffline ? 'حفظ محلياً' : 'انشاء حساب',
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
                                  MaterialPageRoute(builder: (context) => LoginScreen()),
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
                if (controller.isLoading)
                  Container(
                    color: Colors.black.withValues(alpha: 0.5),
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
                                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                              ),
                              SizedBox(height: 15),
                              Text(
                                controller.isOffline
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
                                controller.isOffline
                                    ? 'سيتم إنشاء الحساب عند توفر الاتصال'
                                    : 'يرجى الانتظار',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
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
        },
      ),
    );
  }

  // دوال بناء الـ UI (مستخرجة من الكود الأصلي)
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