// lib/views/email_verification_view.dart
import 'package:fkra/controller/login_controller.dart';
import 'package:fkra/view/login_view.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class EmailVerificationScreen extends StatelessWidget {
  final String email;
  const EmailVerificationScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginController(),
      child: Consumer<LoginController>(
        builder: (context, controller, child) {
          final colorScheme = Theme.of(context).colorScheme;

          return Scaffold(
            appBar: AppBar(
              title: Text(
                'التحقق من البريد الإلكتروني',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              centerTitle: true,
              backgroundColor: colorScheme.surface,
              elevation: 0,
              automaticallyImplyLeading: false,
            ),
            body: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mark_email_unread_outlined,
                      size: 80,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'تحقق من بريدك الإلكتروني',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'تم إرسال رسالة تحقق إلى:',
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        email,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'يرجى فتح بريدك الإلكتروني والضغط على رابط التحقق',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: 280,
                      height: 45,
                      child: ElevatedButton.icon(
                        onPressed: controller.isResendingVerification
                            ? null
                            : () async {
                                await controller.resendEmailVerification();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        controller.verificationMessage ?? 'حدث خطأ',
                                        style: TextStyle(fontSize: 16),
                                      ),
                                      backgroundColor:
                                          controller.verificationMessage != null &&
                                                  controller.verificationMessage!.contains('تم')
                                              ? Colors.green
                                              : Colors.red,
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              },
                        icon: controller.isResendingVerification
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : Icon(Icons.email_outlined, color: colorScheme.onPrimary),
                        label: Text(
                          controller.isResendingVerification
                              ? 'جاري الإرسال...'
                              : 'إعادة إرسال رسالة التحقق',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: 280,
                      height: 45,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final bool isVerified = await controller.checkEmailVerified();
                          if (!context.mounted) return;
                          if (isVerified) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم التحقق من بريدك بنجاح! يرجى تسجيل الدخول',
                                  style: TextStyle(fontSize: 16),
                                ),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (context) => LoginScreen()),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'البريد الإلكتروني لم يتم التحقق منه بعد. يرجى المحاولة مرة أخرى.',
                                  style: TextStyle(fontSize: 16),
                                ),
                                backgroundColor: Colors.orange,
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        },
                        icon: Icon(Icons.refresh, color: colorScheme.primary),
                        label: Text(
                          'لقد تحققت من بريدي',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colorScheme.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextButton(
                      onPressed: () async {
                        await controller.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (context) => LoginScreen()),
                          );
                        }
                      },
                      child: Text(
                        'تسجيل الخروج',
                        style: TextStyle(
                          color: colorScheme.error,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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