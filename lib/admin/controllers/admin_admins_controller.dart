// lib/admin/controllers/admin_admins_controller.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/admin_models.dart';
import '../models/admin_role.dart';
import '../services/admin_api.dart';
import '../services/admin_firestore_service.dart';

const String kProtectedAdminEmail = 'abdullahalmjudi@gmail.com';

class AdminAdminsController extends ChangeNotifier {
  List<AdminMember> admins = [];
  List<UserSnapshot> searchResults = [];

  bool isLoading = true;
  bool isSearching = false;
  bool isActing = false;
  String? error;
  String? success;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _adminsSub;
  Timer? _debounce;

  String? get _actorUid => FirebaseAuth.instance.currentUser?.uid;

  /// المديرون العامون النشطون حالياً (لسياسة "آخر مدير عام").
  int get activeSuperAdmins =>
      admins.where((a) => a.status == 'active' && a.role == AdminRole.superAdmin).length;

  bool _isUidSelf(String uid) => _actorUid != null && uid == _actorUid;

  bool _isProtected(String? email) =>
      (email ?? '').trim().toLowerCase() == kProtectedAdminEmail;

  bool _isCurrentlySuper(String uid, {UserSnapshot? user}) {
    for (final a in admins) {
      if (a.uid == uid) return a.status == 'active' && a.role == AdminRole.superAdmin;
    }
    return user != null && user.isSuperAdmin;
  }

  /// الدالة غير منشورة/غير متاحة (وليس رفض صلاحيات من الخادم) — فقط عندها
  /// يُسمح بالكتابة المباشرة كـ fallback.
  bool _isUnavailable(String message) {
    final s = message.toLowerCase();
    return s.contains('غير منشورة') ||
        s.contains('not-found') ||
        s.contains('unavailable') ||
        s.contains('network');
  }

  Future<void> _record(String action, String uid, String role) async {
    final actor = _actorUid;
    if (actor == null) return;
    await AdminFirestoreService.instance.addAuditLog(
      actorUid: actor,
      action: action,
      result: 'success',
      details: {'uid': uid, 'role': role},
    );
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    _adminsSub?.cancel();
    try {
      _adminsSub = AdminFirestoreService.instance.adminUsersStream().listen((snap) {
        admins = snap.docs.map(AdminMember.fromDoc).toList();
        isLoading = false;
        error = null;
        notifyListeners();
      }, onError: (Object e) {
        error = e.toString();
        isLoading = false;
        notifyListeners();
      });
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  /// بحث مبدئي بعد سكون الكتابة (~400ms) كما في قسم المستخدمين.
  Future<void> searchUsers(String query) async {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      searchResults = [];
      isSearching = false;
      notifyListeners();
      return;
    }
    isSearching = true;
    notifyListeners();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        searchResults =
            await AdminFirestoreService.instance.searchUsers(query, limit: 20);
      } catch (_) {
        searchResults = [];
      }
      isSearching = false;
      notifyListeners();
    });
  }

  Future<bool> setRole({
    required String uid,
    required String role,
    String? email,
    String? displayName,
    UserSnapshot? user,
  }) async {
    error = null;
    success = null;
    if (_isUidSelf(uid)) {
      error = 'لا يمكنك تعديل صلاحياتك الخاصة';
      notifyListeners();
      return false;
    }
    if (_isProtected(email) && role != 'super_admin') {
      error = 'هذا الحساب محمي ولا يمكن تغيير دوره';
      notifyListeners();
      return false;
    }
    if (role != 'super_admin' && _isCurrentlySuper(uid, user: user)) {
      if (activeSuperAdmins <= 1) {
        error = 'يجب أن يبقى مدير عام واحد على الأقل';
        notifyListeners();
        return false;
      }
    }

    isActing = true;
    notifyListeners();
    try {
      try {
        // المسار الأساسي: Callable Function (تحقق الخادم + audit إلزامي).
        await AdminApi.instance.setAdminRole(
          uid: uid,
          role: role,
          email: email,
          displayName: displayName,
        );
      } catch (e) {
        final message = e.toString();
        if (!_isUnavailable(message)) rethrow;
        // Fallback آمن: فقط عندما تكون الدالة غير منشورة/غير متاحة —
        // كتابة مباشرة + audit محلي كتعويض.
        await AdminFirestoreService.instance.setDbAdminRole(
          uid: uid,
          role: role,
          email: email ?? '',
          displayName: displayName ?? email ?? '',
        );
        await _record('admin_role_set', uid, role);
      }
      success = 'تم تحديث الدور بنجاح';
      isActing = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isActing = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeRole(AdminMember member) async {
    error = null;
    success = null;
    if (_isUidSelf(member.uid)) {
      error = 'لا يمكنك تعديل صلاحياتك الخاصة';
      notifyListeners();
      return false;
    }
    if (member.protected && member.role == AdminRole.superAdmin) {
      error = 'هذا الحساب محمي ولا يمكن إزالة صلاحياته';
      notifyListeners();
      return false;
    }
    if (member.role == AdminRole.superAdmin && activeSuperAdmins <= 1) {
      error = 'يجب أن يبقى مدير عام واحد على الأقل';
      notifyListeners();
      return false;
    }

    isActing = true;
    notifyListeners();
    try {
      try {
        await AdminApi.instance.removeAdminRole(uid: member.uid);
      } catch (e) {
        final message = e.toString();
        if (!_isUnavailable(message)) rethrow;
        await AdminFirestoreService.instance.removeDbAdminRole(member.uid);
        await _record('admin_role_removed', member.uid, member.role?.key ?? '');
      }
      success = 'تمت إزالة دور المدير';
      isActing = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isActing = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _adminsSub?.cancel();
    super.dispose();
  }
}