import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:fkra/services/account_access_guard.dart';
import 'package:fkra/services/account_status_service.dart';
import 'package:fkra/services/activity_service.dart';
import 'package:fkra/services/analytics_service.dart';
import 'package:fkra/services/fcm_token_service.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:fkra/model/login_model.dart';
import 'package:fkra/view/login_view.dart';
import 'package:fkra/view/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/home_page.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseUsageTracker.instance.init();
  FcmTokenService.init();
  runApp(const MyApp());
}

/// يمنع تكرار فرض الخروج عند تغيّر الحالة ودورة الحياة معاً.
class AccountEnforcementGate {
  AccountEnforcementGate._();
  static bool isHandling = false;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // `context` هنا فوق `MaterialApp`، فـ`Navigator.of(context)` لا يجد
  // Navigator أصلاً (يرمي No Navigator widget found). نستخدم navigatorKey
  // للوصول إلى الـ navigator الحقيقي مهما كان ترتيب الشجرة.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {

    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // المراقبة الدورية تُطلق نفس مسار الإخراج عند اكتشاف تقييد أثناء الاستخدام.
    AccountStatusService.instance.addListener(_onAccountStateChanged);
    // الحارس يراقب حالة *المالك* أيضاً: إيقاف المالك يجب أن يُخرج تابعيه
    // أثناء الاستخدام (وكذلك إيقافهم أثناء فتح التطبيق أو العودة له).
    AccountAccessGuard.instance.addListener(_onAccessChanged);
  }

  /// يُستدعى من `AccountStatusService` عند تغيّر حالة حساب المستخدم نفسه.
  void _onAccountStateChanged() {
    if (AccountStatusService.instance.state != AccountAccessState.suspended) {
      return;
    }
    _applyEnforcement(EffectiveAccess.suspendedBySelf);
  }

  /// يُستدعى من `AccountAccessGuard` — يلتقط تغيّر "الوصول الفعلي".
  void _onAccessChanged() {
    final access = AccountAccessGuard.instance.access;
    if (access == null) return;
    // إيقاف المالك أثناء الاستخدام ⇒ إسقاط التفويض لا إنهاء الجلسة.
    if (access.requiresPersonalScope) {
      _dropDelegationScope();
      return;
    }
    if (access.isBlocked) {
      _applyEnforcement(access);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AccountStatusService.instance.removeListener(_onAccountStateChanged);
    AccountAccessGuard.instance.removeListener(_onAccessChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // تسجيل نشاط عند العودة للتطبيق (مكبوح زمنياً بـ 15 دقيقة تلقائياً)
      ActivityService.recordActivity();

      // إعادة فحص حالة الحساب عند كل عودة للواجهة: يغطي "الجلسة القديمة"
      // أي حساب تقيُّد أثناء بقاء التطبيق مفتوحاً أو في الخلفية.
      // ملاحظة: الفحص لا يمنع الرسم (لا قفزة شاشة عند كل عودة) بل عند
      // اكتشاف تقييد فعلي فقط.
      _enforceAccountStatus();
    }
  }

  /// يكمل signOutPlatform() جزئياً، لذا نبقيه هنا كطبقة أمان ثانية.
  ///
  /// ⚠️ كان يقرأ حالة المستخدم المسجّل فقط، فالتابع النشط لمالك موقوف
  /// كان يمرّ بلا إجراء. الآن الفحص يشمل المالك عبر الحارس.
  Future<void> _enforceAccountStatus() async {
    final access = await AccountAccessGuard.instance.evaluate();

    // ⭐ إيقاف المالك أثناء الاستخدام: ألغِ التفويض وأعد المستخدم إلى
    // حسابه الشخصي (تبقى الجلسة). كان يُخرج المستخدم من حسابه أيضاً.
    if (access.requiresPersonalScope) {
      await _dropDelegationScope();
      return;
    }

    if (!access.isBlocked) return;
    _applyEnforcement(access);
  }

  /// إسقاط نطاق التفويض وإعادته لحسابه الشخصي دون إنهاء الجلسة.
  Future<void> _dropDelegationScope() async {
    if (!mounted) return;
    if (AccountEnforcementGate.isHandling) return;
    AccountEnforcementGate.isHandling = true;
    try {
      await MemberSessionService.instance.switchToPersonal();
      AccountAccessGuard.instance.stopOwnerWatch();
      if (!mounted) return;
      // واجهة الصفحة الحالية مبنية على `ownerUid` المعلق، فبقيت تعرض
      // بيانات المالك الموقوف في الذاكرة. نعيد بناءها من الحساب الشخصي.
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => Homepage(userId: uid),
        ),
        (route) => false,
      );
    } finally {
      AccountEnforcementGate.isHandling = false;
    }
  }

  /// إنهاء الجلسة فعلياً وإعادة المستخدم لشاشة الدخول مع سبب واضح.
  Future<void> _applyEnforcement(EffectiveAccess access) async {
    if (!mounted) return;
    if (AccountEnforcementGate.isHandling) return;
    AccountEnforcementGate.isHandling = true;
    try {
      // مسح الجلسة أولاً: يمنع إعادة إجبار المستخدم على حساب المالك عند
      // الإقلاع التالي (تفضيل الجلسة المحفوظ يُعاد تطبيقه في Splash).
      await MemberSessionService.instance.clearSession();
      AccountAccessGuard.instance.reset();
      await LoginModel.signOutPlatform();
      await LoginModel.clearSessionPrefs();
      if (!mounted) return;
      // نفس مسار `AccountDeletionService.redirectToLogin`: ننتظر إطاراً
      // حتى يستقرّ بناء القائمة (بسبب تصفير الجلسة) قبل تدمير المكدس.
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            notice: access.notice,
            // `context` هنا فوق `MaterialApp` ⇒ لا يوجد Theme ancestor،
            // فنستخدم لوناً ثابتاً بدل `Theme.of(context)`.
            noticeColor: const Color(0xFFD32F2F),
          ),
        ),
        (route) => false,
      );
    } finally {
      AccountEnforcementGate.isHandling = false;
    }
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'تسهيل',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [
        AnalyticsService.instance.observer,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        fontFamily: 'Cairo',
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        fontFamily: 'Cairo',
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      themeMode: ThemeMode.system,
      // SafeArea سفلي عام: يمنع محتوى التطبيق والأزرار من الاختفاء خلف
      // أزرار النظام الثلاثة (شريط التنقل السفلي في أندرويد).
      builder: (context, child) => SafeArea(top: false, child: child!),
      home: const SplashScreen(),
    );
  }
}
