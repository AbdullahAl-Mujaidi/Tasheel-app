import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/home_page.dart';
import 'package:fkra/admin/admin_portal.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:fkra/model/account_model.dart';
import 'package:fkra/model/login_model.dart';
import 'package:fkra/services/activity_service.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:fkra/view/change_temporary_password_view.dart';
import 'package:fkra/view/login_view.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fkra/admin/services/admin_session_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    // 1. تشغيل مزامنة الحسابات المعلقة في الخلفية (غير حاجزة)
    unawaited(_syncPendingAccountsInBackground());

    // 2. مهلة العرض البصري الدنيا الشفافة (1 ثانية)
    final splashDelay = Future.delayed(const Duration(seconds: 1));

    // 3. انتظار اكتمال استعادة جلسة FirebaseAuth المحفوظة إذا وُجدت —
    //    حتى لا يُفتح مستخدم مسجَّل (كالموظف المُرقّى إلى مدير) كـ"زائر"
    //    عبر SharedPreferences ويُحرم من لوحة الإدارة رغم استيفائه للدور.
    final savedPrefs = await SharedPreferences.getInstance();
    final hasSavedSession = (savedPrefs.getString('user_id') ?? '').isNotEmpty &&
        (savedPrefs.getBool('is_logged_in') ?? false);
    if (FirebaseAuth.instance.currentUser == null && hasSavedSession) {
      try {
        await FirebaseAuth.instance
            .authStateChanges()
            .timeout(const Duration(seconds: 3))
            .first;
      } catch (_) {
        // دون اتصال أو لا جلسة قابلة للاستعادة — يُعالَج عبر المسار المحفوظ أدناه.
      }
    }

    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      // محاولة تحديث بيانات المستخدم سريعا (800ms مهلة كحد أقصى)
      bool reloaded = false;
      try {
        await currentUser.reload().timeout(const Duration(milliseconds: 800));
        currentUser = FirebaseAuth.instance.currentUser;
        reloaded = true;
      } catch (_) {
        // دون إنترنت — نستخدم البيانات المحفوظة محلياً فوراً
      }

      // حلّ جلسة المستخدم التابع (من الكاش محلياً ثم من الخادم عند الاتصال)
      // قبل بوابة التحقق من البريد — التابع يملك حساباً بموافقة المالك.
      await MemberSessionService.instance.resolveForCurrentUser().timeout(
            const Duration(seconds: 4),
            onTimeout: () async {},
          );
      final memberSession = MemberSessionService.instance;

      // بوابة التحقق من البريد: واجبة للمالك فقط وليس للمستخدم التابع.
      if (reloaded &&
          currentUser != null &&
          !currentUser.emailVerified &&
          !memberSession.isSubUser) {
        await LoginModel.signOutPlatform();
        await LoginModel.clearSessionPrefs();

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }

      String userId = currentUser!.uid;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_email', currentUser.email ?? '');

      // تسجيل النشاط في الخلفية بدون حجز الواجهة
      unawaited(ActivityService.record(
        userId: userId,
        isLogin: true,
        method: currentUser.email != null ? 'email' : null,
      ));

      // منع دخول الحسابات المعلّقة من لوحة المدير (مع مهلة قصيرة 800ms)
      try {
        final profile = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(milliseconds: 800));
        FirebaseUsageTracker.instance.recordRead();
        final status = profile.data()?['status']?.toString();
        if (profile.exists && (status == 'blocked' || status == 'suspended')) {
          await LoginModel.signOutPlatform();
          await LoginModel.clearSessionPrefs();
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          }
          return;
        }
      } catch (_) {
        // دون اتصال: لا يمكن التحقق — نسمح بالدخول بحالة الجلسة المحلية
      }

      // تحديد الدور (مع مهلة قصيرة 800ms للمرور السريع دون إنترنت)
      dynamic adminRole;
      try {
        adminRole = await AdminSessionService.instance
            .resolveCurrentRole()
            .timeout(const Duration(milliseconds: 800));
      } catch (_) {
        adminRole = AdminSessionService.instance.role;
      }

      await splashDelay;

      if (mounted) {
        // المستخدم التابع: يرتبط ببيانات صاحب الحساب فقط.
        if (memberSession.isSubUser) {
          final member = memberSession.member;
          // موقوف/محذوف على مستوى العضوية لا يدخل — قواعد الأمان تحجب
          // بيانات المالك عنه فوراً حتى قبل هذه النقطة.
          if (member != null && member.status != 'active') {
            await LoginModel.signOutPlatform();
            await MemberSessionService.instance.clearSession();
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            }
            return;
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => memberSession.mustChangePassword
                  ? ChangeTemporaryPasswordPage(ownerUid: memberSession.ownerUid)
                  : Homepage(
                      userId: memberSession.ownerUid,
                      memberUid: memberSession.authUid,
                    ),
            ),
          );
        } else if (adminRole != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AdminPortal(role: adminRole, uid: userId),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => Homepage(userId: userId),
            ),
          );
        }
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString('user_id');
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

      await splashDelay;

      if (savedUserId != null && isLoggedIn) {
        // دون اتصال/جلسة محفوظة: تحديد ما إذا كان المستخدم تابعاً من الجلسة
        // المخزنة حتى لا يُعامل كمالك (كل الصلاحيات تظهر خطأً).
        final persisted =
            await MemberSessionService.instance.loadPersistedSession();
        await MemberSessionService.instance.resolvePersistedSessionOffline(
          savedUserId,
          persisted?.memberUid,
        );
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => Homepage(
                userId: savedUserId,
                memberUid: persisted?.memberUid,
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      }
    }
  }

  Future<void> _syncPendingAccountsInBackground() async {
    try {
      final pendingSync = AccountModel();
      if (await pendingSync.hasInternet()) {
        await pendingSync.syncPendingAccounts();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business, size: 80, color: colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              'تسهيل',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              'جاري التحميل...',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

