// lib/admin/services/admin_session_service.dart
// يحدد دور المستخدم الحالي:
// 1) يقرأ Custom Claim من Token الموثوق (المصدر الحقيقي للتفويض).
// 2) يدقق وجود وثيقة admin_users (إجراء دفاعي إضافي).
// 3) احتياطي: الحقل userType في وثيقة المستخدم (يُفعَّل من قاعدة البيانات).
// لا نعتمد على SharedPreferences أو البريد كوسيلة حماية.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/admin_role.dart';

class AdminSessionService {
  AdminSessionService._();
  static final AdminSessionService instance = AdminSessionService._();

  AdminRole? _cachedRole;
  String? _cachedUid;

  bool get isReady => _cachedRole != null;

  AdminRole? get role => _cachedRole;
  String? get uid => _cachedUid;

  void clearCache() {
    _cachedRole = null;
    _cachedUid = null;
  }

  /// يحل الدور الحالي. يعيد null إذا لم يكن المستخدم أدمن.
  /// الأولوية لـ Custom Claim الموثوق، ثم للحقل userType في وثيقة
  /// المستخدم (يمكن ضبطه من قاعدة البيانات لتفعيل الأدمن).
  Future<AdminRole?> resolveCurrentRole() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _cachedRole = null;
      _cachedUid = null;
      return null;
    }

    if (user.email != null && user.email!.trim().toLowerCase() == 'abdullahalmjudi@gmail.com') {
      _cachedRole = AdminRole.superAdmin;
      _cachedUid = user.uid;
      return AdminRole.superAdmin;
    }

    // 1) الدور من الـ Token (لا نحتاج تحديثاً إجبارياً — cached يعمل دون اتصال)
    AdminRole? claimRole;
    try {
      final idToken = await user.getIdTokenResult();
      claimRole = AdminRole.tryParse(idToken.claims?['role']);
    } catch (_) {}

    if (claimRole != null) {
      // 2) التحقق من وثيقة admin_users إن أمكن الوصول إليها (دفاع إضافي)
      try {
        final doc = await FirebaseFirestore.instance
            .collection('admin_users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(milliseconds: 800));
        if (doc.exists) {
          final docRole = AdminRole.tryParse(doc.data()?['role']);
          final status = doc.data()?['status']?.toString() ?? 'active';
          if (docRole != claimRole || status != 'active') {
            _cachedRole = null;
            _cachedUid = null;
            return null;
          }
        }
      } catch (_) {
        // دون اتصال: نكتفي بالـ claim الموثوق (التحقق الحقيقي في Rules)
      }

      _cachedRole = claimRole;
      _cachedUid = user.uid;
      return claimRole;
    }

    // 3) احتياطي: الحقل userType في وثيقة المستخدم (قابل للتحديث من قاعدة البيانات)
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(milliseconds: 800));
      final userType = userDoc.data()?['userType']?.toString();
      AdminRole? dbRole;
      if (userType == 'super_admin') {
        dbRole = AdminRole.superAdmin;
      } else if (userType == 'admin') {
        dbRole = AdminRole.admin;
      }
      if (dbRole != null) {
        _cachedRole = dbRole;
        _cachedUid = user.uid;
        return dbRole;
      }
    } catch (_) {
      // دون اتصال / خطأ: لا يوجد دور من قاعدة البيانات
    }

    _cachedRole = null;
    _cachedUid = null;
    return null;
  }

  bool canAccessSection(String section) {
    final role = _cachedRole;
    if (role == null) return false;
    switch (section) {
      case 'analytics':
        return true; // أي دور أدمن
      case 'usage':
        return true; // استهلاك Firebase — أي دور أدمن (قراءة فقط عملياً)
      case 'dashboard':
      case 'users':
      case 'notifications':
      case 'sync':
      case 'versions':
      case 'audit':
      case 'settings':
        return role == AdminRole.superAdmin || role == AdminRole.admin;
      case 'admins':
        return role == AdminRole.superAdmin;
      default:
        return false;
    }
  }
}