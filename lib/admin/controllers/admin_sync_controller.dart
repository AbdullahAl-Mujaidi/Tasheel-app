// lib/admin/controllers/admin_sync_controller.dart
// يعتمد على ما يبلغه تطبيق المستخدم للخادم فقط (lastSyncAt/lastActivityAt).
import 'package:flutter/foundation.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';

enum SyncCategory { upToDate, delayed, stopped, unknown }

class AdminSyncController extends ChangeNotifier {
  List<UserSnapshot> _all = [];
  List<UserSnapshot> users = [];

  bool isLoading = true;
  String? error;

  String _query = '';
  String _statusFilter = 'all'; // all | upToDate | delayed | stopped

  /// عدد الحسابات "المتوقفة" الذي يعتبر تنبيهاً في أعلى الصفحة.
  static const int alertThreshold = 5;

  String get query => _query;
  String get statusFilter => _statusFilter;

  /// تصنيف حالة المزامنة حسب آخر مزامنة:
  /// محدّث < 24 ساعة، متأخر حتى 7 أيام، متوقف بعدها، بدون مزامنة إن لم يُسجَّل.
  static SyncCategory categoryOf(UserSnapshot u) {
    final last = u.lastSyncAt;
    if (last == null) return SyncCategory.unknown;
    final diff = DateTime.now().difference(last);
    if (diff.inHours < 24) return SyncCategory.upToDate;
    if (diff.inHours < 24 * 7) return SyncCategory.delayed;
    return SyncCategory.stopped;
  }

  static String labelOf(SyncCategory c) {
    switch (c) {
      case SyncCategory.upToDate:
        return 'محدّث';
      case SyncCategory.delayed:
        return 'متأخر';
      case SyncCategory.stopped:
        return 'متوقف';
      case SyncCategory.unknown:
        return 'لا توجد مزامنة';
    }
  }

  int get stoppedCount => _all.where((u) => categoryOf(u) == SyncCategory.stopped).length;

  set query(String value) {
    _query = value;
    _applyFilter();
  }

  set statusFilter(String value) {
    _statusFilter = value;
    _applyFilter();
  }

  void _applyFilter() {
    final q = _query.trim().toLowerCase();
    users = _all.where((u) {
      final matchesQuery = q.isEmpty ||
          u.fullName.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
      final matchesStatus = _statusFilter == 'all' ||
          categoryOf(u).name == _statusFilter;
      return matchesQuery && matchesStatus;
    }).toList();
    notifyListeners();
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      _all = (await AdminFirestoreService.instance.fetchLatestByActivity(limit: 200)).users;
      _applyFilter();
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }
}