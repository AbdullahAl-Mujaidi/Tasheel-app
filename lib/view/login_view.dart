// lib/views/login_view.dart
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:fkra/home_page.dart';
import 'package:fkra/admin/admin_portal.dart';
import 'package:fkra/admin/services/admin_session_service.dart';
import 'package:fkra/controller/login_controller.dart';
import 'package:fkra/model/login_model.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:fkra/view/account_view.dart';
import 'package:fkra/view/change_temporary_password_view.dart';
import 'package:fkra/view/email_verification_view.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// توجيه المستخدم بعد تسجيل الدخول حسب دور الحساب:
//  - مستخدم تابع (Sub-user) → بيانات مالك الحساب (ownerUid) + إجبار على تغيير
//    كلمة المرور المؤقتة عند اللزوم.
//  - مدير (userType/Admin Custom Claim) → لوحة المدير.
//  - وإلا → تطبيق المالك.
Future<void> _goToHome(BuildContext context, String userId) async {
  // حلّ العضوية أولاً (من الكاش المحلي ثم من الخادم) لمعرفة صاحب الحساب.
  await MemberSessionService.instance.resolveForCurrentUser();
  if (!context.mounted) return;

  final session = MemberSessionService.instance;

  if (session.isSubUser) {
    final member = session.member;
    // موقوف/محذوف على مستوى العضوية لا يدخل.
    if (member != null && member.status != 'active') {
      await MemberSessionService.instance.clearSession();
      await LoginModel.signOutPlatform();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => session.mustChangePassword
            ? ChangeTemporaryPasswordPage(ownerUid: session.ownerUid)
            : Homepage(userId: session.ownerUid, memberUid: session.authUid),
      ),
    );
    return;
  }

  final adminRole = await AdminSessionService.instance.resolveCurrentRole();
  if (!context.mounted) return;
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => adminRole != null
          ? AdminPortal(role: adminRole, uid: userId)
          : Homepage(userId: userId),
    ),
  );
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginController(),
      child: Consumer<LoginController>(
        builder: (context, controller, child) {
          final colorScheme = Theme.of(context).colorScheme;
          final isDarkMode = Theme.of(context).brightness == Brightness.dark;

          // التحقق من نجاح المزامنة
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (controller.pendingSyncSuccess != null) {
              final userId = controller.pendingSyncSuccess!;
              controller.clearPendingSyncSuccess();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ تم تسجيل الدخول بنجاح بعد عودة الاتصال'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
              _goToHome(context, userId);
            }
          });

          return Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (controller.isOffline)
                      Container(
                        margin: EdgeInsets.only(bottom: 20),
                        padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off, size: 16, color: Colors.orange),
                            SizedBox(width: 8),
                            Text(
                              'وضع غير متصل - سيتم تسجيل الدخول عند عودة الاتصال',
                              style: TextStyle(color: Colors.orange[700], fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    Icon(Icons.business, size: 80, color: colorScheme.primary),
                    Text(
                      'تسهيل',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    Text(
                      'ادارة مهنتك بسهولة',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: 350,
                      height: 450,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: isDarkMode
                                ? Colors.black.withValues(alpha: 0.5)
                                : Colors.grey.withValues(alpha: 0.3),
                            spreadRadius: 5,
                            blurRadius: 7,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 30),
                          Text(
                            "تسجيل الدخول",
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 30),
                          Form(
                            key: controller.formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: controller.emailController,
                                  validator: controller.validateEmail,
                                  autovalidateMode: AutovalidateMode.onUserInteraction,
                                  style: TextStyle(color: colorScheme.onSurface),
                                  decoration: InputDecoration(
                                    hintText: 'ادخل اسم البريد الالكتروني الخاص بك',
                                    labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                                    hintStyle: TextStyle(
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: colorScheme.error, width: 2),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: colorScheme.outline),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: colorScheme.outline),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: colorScheme.primary, width: 2),
                                    ),
                                    prefixIcon: Icon(Icons.email, color: colorScheme.primary),
                                  ),
                                ),
                                const SizedBox(height: 40),
                                StatefulBuilder(
                                  builder: (context, setState) {
                                    bool isPasswordVisible = false;
                                    return TextFormField(
                                      validator: controller.validatePassword,
                                      controller: controller.passwordController,
                                      obscureText: !isPasswordVisible,
                                      autovalidateMode: AutovalidateMode.onUserInteraction,
                                      style: TextStyle(color: colorScheme.onSurface),
                                      decoration: InputDecoration(
                                        hintText: 'ادخل كلمة السر الخاصة بك',
                                        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                                        hintStyle: TextStyle(
                                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: colorScheme.error, width: 2),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: colorScheme.outline),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: colorScheme.outline),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: colorScheme.primary, width: 2),
                                        ),
                                        prefixIcon: Icon(Icons.password, color: colorScheme.primary),
                                        suffixIcon: InkWell(
                                          onTap: () {
                                            setState(() {
                                              isPasswordVisible = !isPasswordVisible;
                                            });
                                          },
                                          child: Icon(
                                            Icons.visibility_off,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: controller.isLoading ? null : () async {
                                    final result = await controller.handleLogin(context);
                                    if (!context.mounted) return;
                                    if (result == 'validation_error') {
                                      AwesomeDialog(
                                        context: context,
                                        title: "تنبيه",
                                        desc: "يرجى إدخال البيانات بشكل صحيح",
                                        dialogType: DialogType.warning,
                                        btnOkText: "حسناً",
                                        btnOkOnPress: () {},
                                      ).show();
                                    } else if (result == 'offline') {
                                      AwesomeDialog(
                                        context: context,
                                        title: "📱 وضع غير متصل",
                                        desc: "لا يوجد اتصال بالإنترنت. تم حفظ بيانات تسجيل الدخول وسيتم تسجيل الدخول تلقائياً عند عودة الاتصال.",
                                        dialogType: DialogType.info,
                                        btnOkText: "حسناً",
                                        btnOkOnPress: () {},
                                      ).show();
                                    } else if (result == 'email_not_verified') {
                                      if (context.mounted) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => EmailVerificationScreen(
                                              email: controller.emailController.text.trim(),
                                            ),
                                          ),
                                        );
                                      }
                                    } else if (result == 'login_failed') {
                                      AwesomeDialog(
                                        context: context,
                                        title: "خطأ",
                                        desc: "البريد الالكتروني او كلمة السر غير صحيحة",
                                        dialogType: DialogType.error,
                                        btnOkText: "حسناً",
                                        btnOkOnPress: () {},
                                      ).show();
                                    } else if (result == 'account_blocked') {
                                      AwesomeDialog(
                                        context: context,
                                        title: "حساب موقوف",
                                        desc: "تم إيقاف حسابك، يرجى التواصل مع إدارة تسهيل.",
                                        dialogType: DialogType.error,
                                        btnOkText: "حسناً",
                                        btnOkOnPress: () {},
                                      ).show();
                                    } else if (result != null && result != 'offline') {
                                      // نجاح تسجيل الدخول
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                            "تم تسجيل الدخول بنجاح",
                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                            textAlign: TextAlign.center,
                                          ),
                                          backgroundColor: colorScheme.primary,
                                          behavior: SnackBarBehavior.floating,
                                          margin: const EdgeInsets.all(15),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                      Future.delayed(const Duration(milliseconds: 500), () {
                                        if (!context.mounted) return;
                                        _goToHome(context, result);
                                      });
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(250, 45),
                                    padding: const EdgeInsets.all(10),
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    elevation: 2,
                                  ),
                                  child: controller.isLoading
                                      ? SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: colorScheme.onPrimary,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (controller.isOffline)
                                              Icon(Icons.save, size: 18, color: colorScheme.onPrimary),
                                            if (controller.isOffline) SizedBox(width: 8),
                                            Text(controller.isOffline ? 'حفظ للمزامنة' : 'دخول'),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: Divider(color: colorScheme.outline)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'أو',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: colorScheme.outline)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: 250,
                      height: 45,
                      child: OutlinedButton.icon(
                        onPressed: controller.isLoading ? null : () async {
                          final result = await controller.handleGoogleLogin(context);
                          if (!context.mounted) return;
                          if (result == 'google_cancelled') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('تم إلغاء تسجيل الدخول بواسطة Google'),
                                backgroundColor: Colors.orange,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          } else if (result == 'google_error' ||
                              result == 'login_failed') {
                            AwesomeDialog(
                              context: context,
                              title: "خطأ",
                              desc: "حدث خطأ أثناء تسجيل الدخول بواسطة Google",
                              dialogType: DialogType.error,
                              btnOkText: "حسناً",
                              btnOkOnPress: () {},
                            ).show();
                          } else if (result != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  "تم تسجيل الدخول بنجاح",
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                backgroundColor: colorScheme.primary,
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(15),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                            Future.delayed(const Duration(milliseconds: 500), () {
                              if (!context.mounted) return;
                              _goToHome(context, result);
                            });
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colorScheme.outline),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: Image.network(
                          'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                          height: 24.0,
                          width: 24.0,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(Icons.g_mobiledata, size: 24, color: colorScheme.primary);
                          },
                        ),
                        label: Text(
                          'تسجيل الدخول بـ Google',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (context) => Accounts()),
                            );
                          },
                          child: Text(
                            "تسجيل حساب جديد",
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "هل لديك حساب ؟ ",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}