
import 'dart:async';
import 'dart:io';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/HomePage.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'firebase_options.dart';
import 'Account.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
      home: const SplashScreen(), // استخدام شاشة البداية للتحقق
    );
  }
}

// ==================== شاشة البداية (Splash Screen) ====================
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
    await Future.delayed(Duration(seconds: 2));

    // ✅ التحقق من Firebase Auth أولاً
    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      // ✅ المستخدم مسجل دخول بالفعل
      String userId = currentUser.uid;
      
      // ✅ تأكيد حفظ userId في SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_email', currentUser.email ?? '');
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => Homepage(userId: userId),
          ),
        );
      }
    } else {
      // ✅ التحقق من الجلسة المحفوظة
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString('user_id');
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      
      if (savedUserId != null && isLoggedIn) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => Homepage(userId: savedUserId),
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
              'تساهيل',
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _FormKey = GlobalKey<FormState>();
  bool isPasswordVisible = false;
  bool isLoading = false;
  bool isOffline = false;
  final TextEditingController controllerEmail = TextEditingController();
  final TextEditingController controllerPassword = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _syncOfflineLogin(); // محاولة مزامنة أي محاولات تسجيل دخول سابقة
  }

  // ==================== التحقق من الاتصال ====================
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkConnectivity() async {
    final hasInternet = await _hasInternet();
    if (mounted) {
      setState(() {
        isOffline = !hasInternet;
      });
    }
  }

  // ==================== حفظ الجلسة محلياً ====================
  Future<void> _saveSessionLocally(String userId, String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // ✅ حفظ معلومات المستخدم الأساسية
      await prefs.setString('user_id', userId);
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_email', email);
      await prefs.setString('login_time', DateTime.now().toIso8601String());
      
      // ✅ حفظ بيانات الجلسة كاملة
      Map<String, dynamic> sessionData = {
        'userId': userId,
        'email': email,
        'loginTime': DateTime.now().toIso8601String(),
      };
      await prefs.setString('logged_in_user', jsonEncode(sessionData));
      
      print('✅ تم حفظ الجلسة للمستخدم: $userId');
    } catch (e) {
      print('خطأ في حفظ الجلسة: $e');
    }
  }

  // ==================== حفظ محاولة تسجيل الدخول عند عدم الاتصال ====================
  Future<void> _saveOfflineLoginAttempt(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> pendingLogins = prefs.getStringList('pending_logins') ?? [];

      Map<String, dynamic> loginData = {
        'email': email,
        'password': password,
        'timestamp': DateTime.now().toIso8601String(),
      };

      pendingLogins.add(jsonEncode(loginData));
      await prefs.setStringList('pending_logins', pendingLogins);
      
      print('📱 تم حفظ محاولة تسجيل الدخول محلياً');
    } catch (e) {
      print('خطأ في حفظ محاولة تسجيل الدخول: $e');
    }
  }

  // ==================== مزامنة محاولات تسجيل الدخول المعلقة ====================
  Future<void> _syncOfflineLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingLogins = prefs.getStringList('pending_logins') ?? [];

    if (pendingLogins.isEmpty) return;

    final bool hasInternet = await _hasInternet();
    if (!hasInternet) return;

    for (String loginJson in pendingLogins) {
      try {
        Map<String, dynamic> loginData = jsonDecode(loginJson);

        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: loginData['email'],
              password: loginData['password'],
            );

        final userId = userCredential.user!.uid;
        final email = loginData['email'];
        
        await _saveSessionLocally(userId, email);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ تم تسجيل الدخول بنجاح بعد عودة الاتصال'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => Homepage(userId: userId)),
          );
        }
        break;
      } catch (e) {
        print('خطأ في مزامنة تسجيل الدخول: $e');
      }
    }

    // ✅ مسح قائمة المحاولات المعلقة بعد المزامنة
    await prefs.remove('pending_logins');
  }

  // ==================== دوال التحقق ====================
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

  @override
  void dispose() {
    controllerEmail.dispose();
    controllerPassword.dispose();
    super.dispose();
  }

  bool checkData() {
    return _FormKey.currentState?.validate() ?? false;
  }

  // ==================== تسجيل الدخول ====================
  Future<User?> checkLogin() async {
    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: controllerEmail.text.trim(),
            password: controllerPassword.text.trim(),
          );
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print("خطأ في تسجيل الدخول: ${e.message}");
      return null;
    }
  }

  Future<void> HandelLogin() async {
    if (isLoading) return;

    if (!checkData()) {
      AwesomeDialog(
        context: context,
        title: "تنبيه",
        desc: "يرجى إدخال البيانات بشكل صحيح",
        dialogType: DialogType.warning,
        btnOkText: "حسناً",
        btnOkOnPress: () {},
      ).show();
      return;
    }

    setState(() {
      isLoading = true;
    });

    final bool hasInternet = await _hasInternet();

    if (!hasInternet) {
      // ✅ حفظ محاولة تسجيل الدخول للمزامنة لاحقاً
      await _saveOfflineLoginAttempt(
        controllerEmail.text.trim(),
        controllerPassword.text.trim(),
      );

      setState(() {
        isLoading = false;
      });

      if (mounted) {
        AwesomeDialog(
          context: context,
          title: "📱 وضع غير متصل",
          desc: "لا يوجد اتصال بالإنترنت. تم حفظ بيانات تسجيل الدخول وسيتم تسجيل الدخول تلقائياً عند عودة الاتصال.",
          dialogType: DialogType.info,
          btnOkText: "حسناً",
          btnOkOnPress: () {},
        ).show();
      }
      return;
    }

    User? user = await checkLogin();

    setState(() {
      isLoading = false;
    });

    if (user != null) {
      // ✅ حفظ الجلسة محلياً
      await _saveSessionLocally(user.uid, controllerEmail.text.trim());
      _loginSuccess(user.uid);
    } else {
      if (mounted) {
        AwesomeDialog(
          context: context,
          title: "خطأ",
          desc: "البريد الالكتروني او كلمة السر غير صحيحة",
          dialogType: DialogType.error,
          btnOkText: "حسناً",
          btnOkOnPress: () {},
        ).show();
      }
    }
  }

  void _loginSuccess(String userId) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "تم تسجيل الدخول بنجاح",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(15),
          duration: const Duration(seconds: 2),
        ),
      );

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => Homepage(userId: userId)),
          );
        }
      });
    }
  }

  // ==================== واجهة المستخدم ====================
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isOffline)
                Container(
                  margin: EdgeInsets.only(bottom: 20),
                  padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'وضع غير متصل - سيتم تسجيل الدخول عند عودة الاتصال',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

              Icon(Icons.business, size: 80, color: colorScheme.primary),
              Text(
                'تساهيل',
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
                          ? Colors.black.withOpacity(0.5)
                          : Colors.grey.withOpacity(0.3),
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
                      key: _FormKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: controllerEmail,
                            validator: validateEmail,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            style: TextStyle(color: colorScheme.onSurface),
                            decoration: InputDecoration(
                              labelText: 'اسم البريد الالكتروني',
                              hintText: 'ادخل اسم البريد الالكتروني الخاص بك',
                              labelStyle: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              hintStyle: TextStyle(
                                color: colorScheme.onSurfaceVariant.withOpacity(
                                  0.5,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.error,
                                  width: 2,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outline,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.email,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                          TextFormField(
                            validator: validatePassword,
                            controller: controllerPassword,
                            obscureText: !isPasswordVisible,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            style: TextStyle(color: colorScheme.onSurface),
                            decoration: InputDecoration(
                              labelText: 'كلمة السر',
                              hintText: 'ادخل كلمة السر الخاصة بك',
                              labelStyle: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              hintStyle: TextStyle(
                                color: colorScheme.onSurfaceVariant.withOpacity(
                                  0.5,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.error,
                                  width: 2,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outline,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.password,
                                color: colorScheme.primary,
                              ),
                              suffixIcon: InkWell(
                                onTap: () {
                                  setState(() {
                                    isPasswordVisible = !isPasswordVisible;
                                  });
                                },
                                child: Icon(
                                  isPasswordVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextButton(
                            onPressed: () {},
                            child: Text(
                              "هل نسيت كلمة السر ؟",
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          ElevatedButton(
                            onPressed: isLoading ? null : HandelLogin,
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
                            child: isLoading
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
                                      if (isOffline)
                                        Icon(
                                          Icons.save,
                                          size: 18,
                                          color: colorScheme.onPrimary,
                                        ),
                                      if (isOffline) SizedBox(width: 8),
                                      Text(isOffline ? 'حفظ للمزامنة' : 'دخول'),
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
  }
}