// lib/admin/controllers/admin_users_controller.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/admin_models.dart';
import '../services/admin_api.dart';
import '../services/admin_firestore_service.dart';

class AdminUsersController extends ChangeNotifier {
  List<UserSnapshot> users = [];
  Map<String, UserCounts> countsByUser = {};

  bool isLoading = true;
  bool isSearching = false;
  bool isActing = false;
  bool isLoadingMore = false;
  bool hasMore = false;
  String? error;
  String _query = '';
  Timer? _debounce;
  DocumentSnapshot? _lastDoc;

  static const int _pageSize = 50;

  String get query => _query;

  set query(String value) {
    if (_query == value) return;
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (_query.trim().isEmpty) {
        load();
      } else {
        search();
      }
    });
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    _lastDoc = null;
    hasMore = false;
    notifyListeners();
    try {
      final page =
          await AdminFirestoreService.instance.fetchUsers(limit: _pageSize);
      _applyPage(page, reset: true);
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore || _lastDoc == null) return;
    isLoadingMore = true;
    notifyListeners();
    try {
      final page = await AdminFirestoreService.instance
          .fetchUsers(limit: _pageSize, startAfter: _lastDoc);
      _applyPage(page, reset: false);
    } catch (_) {
      // لا نوقف القائمة عند فشل الصفحة التالية؛ يمكن للمستخدم المحاولة مجدداً
    }
    isLoadingMore = false;
    notifyListeners();
  }

  void _applyPage(
    ({List<UserSnapshot> users, DocumentSnapshot? last}) page, {
    required bool reset,
  }) {
    final incoming = page.users;
    if (reset) {
      users = List.of(incoming);
      countsByUser = {};
    } else {
      // نفرد حسب UID احتياطاً من أي تكرار أثناء الترقيم
      final merged = {
        ...{for (final u in users) u.uid: u},
        ...{for (final u in incoming) u.uid: u}
      };
      users = merged.values.toList();
    }
    _lastDoc = page.last;
    hasMore = incoming.length >= _pageSize && page.last != null;
    _loadCounts(incoming);
  }

  Future<void> search() async {
    isSearching = true;
    error = null;
    _lastDoc = null;
    hasMore = false;
    notifyListeners();
    try {
      users = await AdminFirestoreService.instance.searchUsers(_query);
      countsByUser = {};
      await _loadCounts(users);
    } catch (e) {
      error = e.toString();
    }
    isSearching = false;
    notifyListeners();
  }

  Future<void> _loadCounts(List<UserSnapshot> target) async {
    if (target.isEmpty) return;
    final counts = await AdminFirestoreService.instance
        .fetchUserCounts(target.map((u) => u.uid).toList());
    countsByUser.addAll({for (final c in counts) c.uid: c});
    notifyListeners();
  }

  int businessCountOf(String uid) => countsByUser[uid]?.businessCount ?? 0;

  String? get _actorUid {
    final u = FirebaseAuth.instance.currentUser;
    return u?.uid;
  }

  Future<void> _record(
    String action,
    UserSnapshot target, {
    String? oldRole,
    String? newRole,
    String? oldStatus,
    String? newStatus,
  }) async {
    final actor = _actorUid;
    if (actor == null) return;
    await AdminFirestoreService.instance.addAuditLog(
      actorUid: actor,
      action: action,
      result: 'success',
      details: {
        'targetUid': target.uid,
        'targetEmail': target.email,
        'targetName': target.fullName,
        if (oldRole != null) 'oldRole': oldRole,
        if (newRole != null) 'newRole': newRole,
        if (oldStatus != null) 'oldStatus': oldStatus,
        if (newStatus != null) 'newStatus': newStatus,
      },
    );
  }

  // الدالة غير منشورة/غير متاحة (وليس رفض صلاحيات من الخادم) — فقط عندها
  // يُسمح بالكتابة المباشرة كـ fallback (يعمل على الخطة المجانية بدون CF).
  bool _isUnavailable(String message) {
    final s = message.toLowerCase();
    return s.contains('غير منشورة') ||
        s.contains('not-found') ||
        s.contains('unavailable') ||
        s.contains('network');
  }

  Future<String?> promoteToAdmin(UserSnapshot u) async {
    return _act(() async {
      // المسار الأساسي: Callable Function — وإن لم تكن منشورة (خطة مجانية)
      // نُحوّل مباشرة عبر قاعدة البيانات مع تسجيل العملية محلياً.
      try {
        await AdminApi.instance.setAdminRole(
          uid: u.uid,
          role: 'admin',
          email: u.email,
          displayName: u.fullName,
        );
      } catch (e) {
        final message = e.toString();
        if (!_isUnavailable(message)) rethrow;
        await AdminFirestoreService.instance.setDbAdminRole(
          uid: u.uid,
          role: 'admin',
          email: u.email,
          displayName: u.fullName,
        );
      }
      await _record('user_promoted_admin', u,
          oldRole: u.userType, newRole: 'admin');
    });
  }

  Future<String?> demoteToUser(UserSnapshot u) async {
    return _act(() async {
      try {
        await AdminApi.instance.removeAdminRole(uid: u.uid);
      } catch (e) {
        final message = e.toString();
        if (!_isUnavailable(message)) rethrow;
        await AdminFirestoreService.instance.removeDbAdminRole(u.uid);
      }
      await _record('user_demoted', u, oldRole: u.userType, newRole: 'user');
    });
  }

  Future<String?> setBlocked(UserSnapshot u, bool blocked) async {
    lastActionUsedFirestoreFallback = false;
    return _act(() async {
      final newStatus = blocked ? 'suspended' : 'active';
      final oldStatus = u.status;
      try {
        await AdminApi.instance.setUserStatus(uid: u.uid, disabled: blocked);
        lastActionUsedFirestoreFallback = false;
      } catch (e) {
        final message = e.toString();
        // لا نتراجع للمسار الاحتياطي إلا لعطل بنية تحتية معروف — مثال:
        // Cloud Functions غير منشورة أو خطأ شبكة.
        if (!_isUnavailable(message)) rethrow;
        
        await _firestoreFallback(u.uid, blocked);
        lastActionUsedFirestoreFallback = true;
      }
      await _record(
        blocked ? 'user_blocked' : 'user_unblocked',
        u,
        oldStatus: oldStatus,
        newStatus: newStatus,
      );
    });
  }

  /// المسار الاحتياطي: يكتب الحالة في Firestore فقط.
  ///
/// ⚠️ حدوده الصريحة: هذا يوقف ما يراه العميل ويمنع القراءة والكتابة عبر
  /// Security Rules، لكنه **لا يعطّل** Firebase Auth ولا يقطع الجلسات القائمة.
  /// لذا نعرض تنبيهاً صريحاً (إعداد ناقص) بدل ادّعاء نجاح كامل، ويجب أن
  /// ينجح المسار الأول.
  Future<void> _firestoreFallback(String uid, bool blocked) async {
    await AdminFirestoreService.instance
        .setUserBlockedStatus(uid: uid, blocked: blocked);
  }

  /// هل نُفِّذ آخر تقييد عبر المسار الاحتياطي (بلا تعطيل Auth)؟
  /// الواجهة تستخدمه لعرض تنبيه صريح بدل ادّعاء النجاح الكامل.
  bool lastActionUsedFirestoreFallback = false;

  Future<String?> deleteUser(UserSnapshot u) async {
    return _act(() async {
      await AdminApi.instance.deleteUser(uid: u.uid);
      await _record('user_deleted', u);
    });
  }

  Future<String?> _act(Future<void> Function() action) async {
    if (isActing) return 'busy';
    isActing = true;
    error = null;
    notifyListeners();
    try {
      await action();
      isActing = false;
      await load();
      notifyListeners();
      return null;
    } catch (e) {
      var msg = e.toString();
      if (msg.contains('not-found') || msg.contains('NOT_FOUND')) {
        msg =
            'خدمة الحذف غير منشورة على الخادم حالياً (Cloud Function deleteUser غير متوفرة على Firebase).';
      } else if (msg.contains('permission-denied') ||
          msg.contains('PERMISSION_DENIED')) {
        msg =
            'تم رفض العملية من قواعد الأمان (Missing permissions). يرجى التأكد من نشر firestore.rules المحدثة.';
      }
      error = msg;
      isActing = false;
      notifyListeners();
      return msg;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
