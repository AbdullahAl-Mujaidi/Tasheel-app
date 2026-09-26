// lib/admin/controllers/admin_dashboard_controller.dart
import 'package:flutter/foundation.dart';

import '../models/admin_models.dart';
import '../services/admin_api.dart';
import '../services/admin_firestore_service.dart';

class AdminDashboardController extends ChangeNotifier {
  DashboardStats? stats;
  List<UserSnapshot> recentUsers = [];
  List<UserSnapshot> recentActiveUsers = [];
  Map<String, UserCounts> countsByUser = {};

  bool isLoading = true;
  String? error;
  bool isRefreshing = false;

  static const Duration _rateLimit = Duration(minutes: 1);

  DateTime? _lastManualRefreshAt;
  bool _sessionExpiredNotified = false;
  bool _disposed = false;

  /// يُستدعى عند اكتشاف فقدان صلاحية الأدمن أثناء الجلسة (permission-denied)
  /// ليقوم ناقل الحركة (الشاشة) بإعادة التوجيه لشاشة الدخول فوراً.
  void Function()? onSessionExpired;

  /// الحد الأدنى بين التحديثات اليدوية (دقيقة واحدة — Rate limiting في الواجهة).
  bool get canRefresh {
    final last = _lastManualRefreshAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _rateLimit;
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      stats = await AdminFirestoreService.instance.fetchDashboardStats();
      recentUsers = (await AdminFirestoreService.instance.fetchUsers(limit: 5)).users;
      recentActiveUsers = (await AdminFirestoreService.instance.fetchLatestByActivity(limit: 5)).users;
      final allUids = {...recentUsers.map((u) => u.uid), ...recentActiveUsers.map((u) => u.uid)}.toList();
      final counts = await AdminFirestoreService.instance.fetchUserCounts(allUids);
      countsByUser = {for (final c in counts) c.uid: c};
    } catch (e) {
      _onSessionError(e);
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  int businessCountOf(String uid) => countsByUser[uid]?.businessCount ?? 0;

  /// تحديث يدوي: يستدعي Cloud Function `refreshStats`، وعند فشلها
  /// fallback لقراءة مستند `admin_stats` المخزّن مباشرة عبر Firestore.
  /// يعيد true إذا تم التحديث عبر الدالة السحابية، و false إذا استُخدمت
  /// البيانات المحفوظة كبديل.
  Future<bool> refresh() async {
    isRefreshing = true;
    notifyListeners();
    var fromCloud = true;
    try {
      try {
        await AdminApi.instance.refreshStats();
      } catch (e) {
        _onSessionError(e);
        fromCloud = false;
      }
      await load();
      _lastManualRefreshAt = DateTime.now();
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
    return fromCloud;
  }

  void _onSessionError(Object e) {
    final s = e.toString();
    if ((s.contains('permission-denied') ||
            s.contains('PERMISSION_DENIED') ||
            s.contains('unauthenticated')) &&
        !_sessionExpiredNotified) {
      _sessionExpiredNotified = true;
      onSessionExpired?.call();
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}